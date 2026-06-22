import Foundation
import LinguistMacCore

@MainActor
extension AppShellModel {
    func runScreenTranslation() async {
        record(.screenTranslate)
        cancelPopupWordLookup()
        let translationSettings = settingsWithSupportedProvider()
        let loadingRequest = TranslationRequest(
            text: "",
            sourceLanguage: translationSettings.sourceLanguage,
            targetLanguage: translationSettings.targetLanguage,
            inputMode: .screenSelection,
            providerID: translationSettings.selectedProviderID
        )
        screenSessionState = .capturing

        let coordinator = ScreenTranslationCoordinator(services: services)
        let finalState = await coordinator.translateScreenSelection(settings: translationSettings)
        screenSessionState = finalState

        switch finalState {
        case let .completed(result):
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)
            await persistRecentTranslation(result)
        case let .failed(failure):
            popupState = .failed(failure, originalText: nil)
        case let .translating(request):
            popupState = .loading(request)
        case .idle, .requestingPermission, .capturing, .recognizing:
            popupState = .loading(loadingRequest)
        }
    }

    func runQuickTranslate() async {
        clearActiveQuickVoiceCapture()
        quickVoiceState = .idle
        quickVoiceTranscript = nil
        await runQuickTranslate(preservingVoiceTranscript: false)
    }

    func startQuickVoiceCapture() {
        guard !isQuickVoiceCaptureActive else {
            return
        }

        record(.quickTranslate)
        cancelPopupWordLookup()
        cancelQuickWordTranslation()
        clearActiveQuickVoiceCapture()
        let captureID = UUID()
        activeQuickVoiceCaptureID = captureID
        quickVoiceState = .capturing
        quickVoiceTranscript = nil
        quickSessionState = .capturing
        activeQuickVoiceCaptureTask = Task {
            await runQuickVoiceCapture(captureID: captureID)
        }
    }

    func cancelQuickVoiceCapture() {
        activeQuickVoiceCaptureTask?.cancel()
    }

    var isQuickVoiceCaptureActive: Bool {
        activeQuickVoiceCaptureID != nil || activeQuickVoiceCaptureTask != nil
    }

    func clearActiveQuickVoiceCapture() {
        activeQuickVoiceCaptureID = nil
        activeQuickVoiceCaptureTask?.cancel()
        activeQuickVoiceCaptureTask = nil
    }

    private func runQuickTranslate(
        preservingVoiceTranscript: Bool,
        voiceCaptureID: UUID? = nil,
        sourceLanguageOverride: TranslationLanguage? = nil
    ) async {
        prepareQuickTranslation(preservingVoiceTranscript: preservingVoiceTranscript)
        do {
            let translationSettings = settingsWithSupportedProvider()
            let request = try await quickTranslationRequest(
                settings: translationSettings,
                sourceLanguageOverride: sourceLanguageOverride
            )
            guard try shouldContinueQuickVoiceCapture(voiceCaptureID) else {
                return
            }
            quickSessionState = .translating(request)
            popupState = .loading(request)

            let translator = try await readyQuickTranslator(for: request)
            guard try shouldContinueQuickVoiceCapture(voiceCaptureID) else {
                return
            }
            let result = try await translator.translate(request)
            guard try shouldContinueQuickVoiceCapture(voiceCaptureID) else {
                return
            }
            await finishQuickTranslation(
                result,
                translator: translator,
                settings: translationSettings,
                voiceCaptureID: voiceCaptureID
            )
        } catch is CancellationError {
            applyQuickTranslationFailure(cancellationFailure(for: voiceCaptureID), voiceCaptureID: voiceCaptureID)
        } catch let failure as TranslationFailure {
            applyQuickTranslationFailure(failure, voiceCaptureID: voiceCaptureID)
        } catch {
            let failure = TranslationFailure.providerFailed(error.localizedDescription)
            applyQuickTranslationFailure(failure, voiceCaptureID: voiceCaptureID)
        }
    }

    private func prepareQuickTranslation(preservingVoiceTranscript: Bool) {
        record(.quickTranslate)
        cancelPopupWordLookup()
        cancelQuickWordTranslation()
        if !preservingVoiceTranscript {
            quickVoiceState = .idle
            quickVoiceTranscript = nil
        }
    }

    private func shouldContinueQuickVoiceCapture(_ captureID: UUID?) throws -> Bool {
        try Task.checkCancellation()
        return isCurrentQuickVoiceCapture(captureID)
    }

    private func finishQuickTranslation(
        _ result: TranslationResult,
        translator: any TranslationProviding,
        settings: AppSettings,
        voiceCaptureID: UUID?
    ) async {
        guard !Task.isCancelled, isCurrentQuickVoiceCapture(voiceCaptureID) else {
            return
        }

        quickSessionState = .completed(result)
        popupState = .success(result, showsOriginal: false)
        saveRecent(result)
        await persistRecentTranslation(result)

        if settings.autoCopyEnabled, isCurrentQuickVoiceCapture(voiceCaptureID) {
            await services.clipboard.writeText(result.translatedText)
        }

        guard !Task.isCancelled, isCurrentQuickVoiceCapture(voiceCaptureID) else {
            return
        }

        guard shouldStartQuickWordTranslation(translator: translator, voiceCaptureID: voiceCaptureID) else {
            return
        }

        startQuickWordTranslation(for: result, translator: translator)
    }

    private func applyQuickTranslationFailure(
        _ failure: TranslationFailure,
        voiceCaptureID: UUID?
    ) {
        guard isCurrentQuickVoiceCapture(voiceCaptureID) else {
            return
        }

        quickSessionState = .failed(failure)
        popupState = .failed(failure, originalText: quickDraft.trimmedText)
    }

    private func cancellationFailure(for voiceCaptureID: UUID?) -> TranslationFailure {
        voiceCaptureID == nil
            ? .providerFailed(CancellationError().localizedDescription)
            : .voiceCaptureCancelled
    }

    private func quickTranslationRequest(
        settings: AppSettings,
        sourceLanguageOverride: TranslationLanguage? = nil
    ) async throws -> TranslationRequest {
        var draft = quickDraft
        if let sourceLanguageOverride {
            draft.sourceLanguage = sourceLanguageOverride
        }

        var request = try draft
            .makeRequest(providerID: settings.selectedProviderID)
            .resolvingAutoDetectedSource()
        let providerID = await services.translatorRegistry.supportedProviderID(
            preferred: request.providerID,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage
        )
        request = request.usingProvider(providerID)
        return request
    }

    private func readyQuickTranslator(for request: TranslationRequest) async throws -> any TranslationProviding {
        let translator = try await services.translatorRegistry.provider(for: request.providerID)
        guard !translator.usesNetwork else {
            return translator
        }

        let readiness = await services.languageAvailability.readiness(
            from: request.sourceLanguage,
            to: request.targetLanguage,
            sampleText: request.text
        )
        switch readiness {
        case .ready, .unknown:
            return translator
        case .needsDownload:
            throw TranslationFailure.missingLanguagePack(request.providerID)
        case .unavailable:
            throw TranslationFailure.unsupportedLanguagePair
        }
    }

    private func runQuickVoiceCapture(captureID: UUID) async {
        let sourceLanguage = quickDraft.sourceLanguage
        guard !sourceLanguage.supportsAutoDetect else {
            await finishQuickVoiceCapture(.failed(.sourceLanguageRequired), captureID: captureID)
            return
        }

        let coordinator = SpeechRecognitionCoordinator(services: services)
        let finalState = await coordinator.captureShortPhrase(sourceLanguage: sourceLanguage) { [weak self] state in
            await self?.applyQuickVoiceState(state, captureID: captureID)
        }

        await finishQuickVoiceCapture(finalState, captureID: captureID, sourceLanguage: sourceLanguage)
    }

    private func applyQuickVoiceState(
        _ state: SpeechRecognitionSessionState,
        captureID: UUID
    ) {
        guard activeQuickVoiceCaptureID == captureID else {
            return
        }

        quickVoiceState = state
        switch state {
        case .idle:
            quickSessionState = .idle
        case let .requestingPermission(kind):
            quickSessionState = .requestingPermission(kind)
        case .capturing:
            quickSessionState = .capturing
        case .recognizing:
            quickSessionState = .recognizing
        case let .completed(result):
            quickVoiceTranscript = result.trimmedTranscript
        case let .failed(failure):
            quickSessionState = .failed(translationFailure(from: failure))
        }
    }

    private func finishQuickVoiceCapture(
        _ finalState: SpeechRecognitionSessionState,
        captureID: UUID,
        sourceLanguage: TranslationLanguage? = nil
    ) async {
        guard activeQuickVoiceCaptureID == captureID else {
            return
        }

        guard case let .completed(result) = finalState else {
            applyQuickVoiceState(finalState, captureID: captureID)
            clearFinishedQuickVoiceCapture(captureID: captureID)
            return
        }

        let transcript = result.trimmedTranscript
        quickVoiceState = finalState
        quickVoiceTranscript = transcript
        quickDraft.sourceText = transcript
        await runQuickTranslate(
            preservingVoiceTranscript: true,
            voiceCaptureID: captureID,
            sourceLanguageOverride: sourceLanguage
        )
        clearFinishedQuickVoiceCapture(captureID: captureID)
    }

    private func clearFinishedQuickVoiceCapture(captureID: UUID) {
        guard activeQuickVoiceCaptureID == captureID else {
            return
        }

        activeQuickVoiceCaptureID = nil
        activeQuickVoiceCaptureTask = nil
    }

    private func isCurrentQuickVoiceCapture(_ captureID: UUID?) -> Bool {
        guard let captureID else {
            return true
        }

        return activeQuickVoiceCaptureID == captureID
    }

    private func translationFailure(from failure: SpeechRecognitionFailure) -> TranslationFailure {
        switch failure {
        case let .permissionDenied(kind):
            .permissionDenied(kind)
        case .sourceLanguageRequired:
            .speechSourceLanguageRequired
        case .onDeviceRecognitionUnavailable:
            .onDeviceSpeechUnavailable
        case .emptyTranscript:
            .noSpeechRecognized
        case .cancelled:
            .voiceCaptureCancelled
        case .captureInProgress:
            .voiceCaptureInProgress
        case .recognitionFailed:
            .speechRecognitionFailed
        }
    }

    private func shouldStartQuickWordTranslation(
        translator: any TranslationProviding,
        voiceCaptureID: UUID?
    ) -> Bool {
        // For voice captures, a network provider should receive only the final transcript request.
        !(voiceCaptureID != nil && translator.usesNetwork)
    }

    private func startQuickWordTranslation(
        for result: TranslationResult,
        translator: any TranslationProviding
    ) {
        let augmentationID = UUID()
        activeQuickWordTranslationID = augmentationID
        activeQuickWordTranslationTask = Task {
            let augmentedResult = await WordTranslationAugmenter.resultWithWordTranslationsIfNeeded(
                result,
                provider: translator,
                eligibleInputModes: [.quickTranslate]
            )
            await finishQuickWordTranslation(
                augmentationID: augmentationID,
                resultID: result.id,
                augmentedResult: augmentedResult
            )
        }
    }

    private func finishQuickWordTranslation(
        augmentationID: UUID,
        resultID: UUID,
        augmentedResult: TranslationResult
    ) async {
        guard activeQuickWordTranslationID == augmentationID else {
            return
        }

        activeQuickWordTranslationID = nil
        activeQuickWordTranslationTask = nil

        guard !Task.isCancelled,
              !augmentedResult.wordTranslations.isEmpty,
              case let .completed(currentQuickResult) = quickSessionState,
              currentQuickResult.id == resultID
        else {
            return
        }

        quickSessionState = .completed(augmentedResult)
        if case let .success(currentPopupResult, showsOriginal, wordCard) = popupState {
            if currentPopupResult.id == resultID {
                popupState = .success(augmentedResult, showsOriginal: showsOriginal, wordCard: wordCard)
            }
        }
        saveRecent(augmentedResult)
        await persistRecentTranslation(augmentedResult)
    }

    func runSelectedTextTranslation() async {
        record(.selectedTextTranslate)
        await runInputModeTranslation(.selectedText) { coordinator, settings in
            await coordinator.translateSelectedText(settings: settings)
        }
    }

    func runClipboardDoubleCopyTranslation() async {
        record(.clipboardDoubleCopyTranslate)
        await runInputModeTranslation(.clipboardDoubleCopy) { coordinator, settings in
            await coordinator.translateClipboardDoubleCopy(settings: settings)
        }
    }

    func runDragTranslation() async {
        record(.dragTranslate)
        await runInputModeTranslation(.dragTranslation) { coordinator, settings in
            await coordinator.translateDragSelection(settings: settings)
        }
    }

    @discardableResult
    func observeCopyCommand(at date: Date = Date()) async -> Bool {
        guard settings.doubleCopyTranslationEnabled,
              doubleCopyTriggerDetector.recordCopyCommand(at: date)
        else {
            return false
        }

        await runClipboardDoubleCopyTranslation()
        return true
    }

    func togglePopupOriginal() {
        popupState = popupState.toggledOriginalVisibility()
    }

    func selectPopupWord(
        _ wordTranslation: WordTranslation,
        at index: Int? = nil,
        resultID expectedResultID: UUID? = nil
    ) async {
        guard case let .success(result, showsOriginal, _) = popupState else {
            return
        }
        guard expectedResultID == nil || result.id == expectedResultID else {
            return
        }

        if await restoreShownPopupWordCard(
            wordTranslation,
            at: index,
            result: result,
            showsOriginal: showsOriginal
        ) {
            return
        }

        let request = wordLookupRequest(for: wordTranslation, result: result)
        let (lookupID, lookupTask) = startPopupWordLookup(
            request: request,
            wordTranslation: wordTranslation,
            wordIndex: index,
            result: result,
            showsOriginal: showsOriginal
        )
        let lookupState = await lookupTask.value
        await finishPopupWordLookup(
            lookupID: lookupID,
            resultID: result.id,
            wordTranslation: wordTranslation,
            wordIndex: index,
            lookupState: lookupState
        )
    }

    private func restoreShownPopupWordCard(
        _ wordTranslation: WordTranslation,
        at index: Int?,
        result: TranslationResult,
        showsOriginal: Bool
    ) async -> Bool {
        guard let shownContent = result.shownWordCard(matching: wordTranslation, at: index) else {
            return false
        }

        cancelPopupWordLookup()
        let updatedResult = result.savingShownWordCard(shownContent)
        popupState = .success(
            updatedResult,
            showsOriginal: showsOriginal,
            wordCard: TranslationPopupWordCardState(shownContent: shownContent, result: updatedResult)
        )
        saveRecent(updatedResult)
        await persistRecentTranslation(updatedResult)
        return true
    }

    private func startPopupWordLookup(
        request: WordLookupRequest,
        wordTranslation: WordTranslation,
        wordIndex: Int?,
        result: TranslationResult,
        showsOriginal: Bool
    ) -> (UUID, Task<WordLookupState, Never>) {
        let lookupID = UUID()
        let loadingCard = TranslationPopupWordCardState(
            wordTranslation: wordTranslation,
            wordIndex: wordIndex,
            lookupState: .loading(request)
        )

        activePopupWordLookupTask?.cancel()
        activePopupWordLookupID = lookupID
        popupState = .success(result, showsOriginal: showsOriginal, wordCard: loadingCard)

        let lookupTask = Task<WordLookupState, Never> {
            let provider = services.wordLookupProvider
            do {
                if let result = try await provider.lookup(request) {
                    return .completed(result)
                }

                return .empty(request)
            } catch let failure as WordLookupFailure {
                return .failed(failure)
            } catch is CancellationError {
                return .failed(.cancelled)
            } catch {
                return .failed(.providerFailed)
            }
        }
        activePopupWordLookupTask = lookupTask
        return (lookupID, lookupTask)
    }

    private func finishPopupWordLookup(
        lookupID: UUID,
        resultID: UUID,
        wordTranslation: WordTranslation,
        wordIndex: Int?,
        lookupState: WordLookupState
    ) async {
        guard activePopupWordLookupID == lookupID else {
            return
        }

        activePopupWordLookupID = nil
        activePopupWordLookupTask = nil

        guard case let .success(currentResult, currentShowsOriginal, _) = popupState,
              currentResult.id == resultID
        else {
            return
        }

        let completedState = completedPopupState(
            result: currentResult,
            showsOriginal: currentShowsOriginal,
            wordTranslation: wordTranslation,
            wordIndex: wordIndex,
            lookupState: lookupState
        )
        popupState = completedState

        guard let shownContent = completedState.wordCard?.shownContent else {
            return
        }

        let updatedResult = currentResult.savingShownWordCard(shownContent)
        popupState = completedPopupState(
            result: updatedResult,
            showsOriginal: currentShowsOriginal,
            wordTranslation: wordTranslation,
            wordIndex: wordIndex,
            lookupState: lookupState
        )
        saveRecent(updatedResult)
        await persistRecentTranslation(updatedResult)
    }

    func dismissPopupWordCard() {
        cancelPopupWordLookup()
        popupState = popupState.updatingWordCard(nil)
    }

    private func cancelPopupWordLookup() {
        activePopupWordLookupID = nil
        activePopupWordLookupTask?.cancel()
        activePopupWordLookupTask = nil
    }

    func cancelQuickWordTranslation() {
        activeQuickWordTranslationID = nil
        activeQuickWordTranslationTask?.cancel()
        activeQuickWordTranslationTask = nil
    }

    private func wordLookupRequest(
        for wordTranslation: WordTranslation,
        result: TranslationResult
    ) -> WordLookupRequest {
        WordLookupRequest(
            sourceText: wordTranslation.sourceText,
            sentenceContext: result.originalText,
            sourceLanguage: result.request.sourceLanguage,
            targetLanguage: result.request.targetLanguage,
            providerID: result.request.providerID,
            inputMode: result.request.inputMode
        )
    }

    private func completedPopupState(
        result: TranslationResult,
        showsOriginal: Bool,
        wordTranslation: WordTranslation,
        wordIndex: Int?,
        lookupState: WordLookupState
    ) -> TranslationPopupState {
        .success(
            result,
            showsOriginal: showsOriginal,
            wordCard: TranslationPopupWordCardState(
                wordTranslation: wordTranslation,
                wordIndex: wordIndex,
                lookupState: lookupState
            )
        )
    }

    private func saveRecent(_ result: TranslationResult) {
        recentTranslations = TranslationHistoryPolicy.inserting(
            result,
            into: recentTranslations,
            limit: TranslationHistoryPolicy.defaultLimit
        )
    }

    private func persistRecentTranslation(_ result: TranslationResult) async {
        do {
            try await services.historyStore.save(result)
            historyLoadError = nil
        } catch {
            handleHistoryPersistenceFailure(error)
        }
    }

    private func runInputModeTranslation(
        _ inputMode: TranslationInputMode,
        operation: (InputModeTranslationCoordinator, AppSettings) async -> TranslationSessionState
    ) async {
        cancelPopupWordLookup()
        let translationSettings = settingsWithSupportedProvider()
        let loadingRequest = TranslationRequest(
            text: "",
            sourceLanguage: translationSettings.sourceLanguage,
            targetLanguage: translationSettings.targetLanguage,
            inputMode: inputMode,
            providerID: translationSettings.selectedProviderID
        )
        inputModeSessionState = .capturing
        popupState = .loading(loadingRequest)

        let coordinator = InputModeTranslationCoordinator(services: services)
        let finalState = await operation(coordinator, translationSettings)
        inputModeSessionState = finalState

        switch finalState {
        case let .completed(result):
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)
        case let .failed(failure):
            popupState = .failed(failure, originalText: nil)
        case let .translating(request):
            popupState = .loading(request)
        case .idle, .requestingPermission, .capturing, .recognizing:
            popupState = .loading(loadingRequest)
        }
    }
}
