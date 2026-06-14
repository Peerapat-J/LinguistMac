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
        record(.quickTranslate)
        cancelPopupWordLookup()
        do {
            let translationSettings = settingsWithSupportedProvider()
            var request = try quickDraft
                .makeRequest(providerID: translationSettings.selectedProviderID)
                .resolvingAutoDetectedSource()
            let providerID = await services.translatorRegistry.supportedProviderID(
                preferred: request.providerID,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage
            )
            request = request.usingProvider(providerID)
            quickSessionState = .translating(request)
            popupState = .loading(request)

            let readiness = await services.languageAvailability.readiness(
                from: request.sourceLanguage,
                to: request.targetLanguage,
                sampleText: request.text
            )
            let translator = try await services.translatorRegistry.provider(for: request.providerID)
            if !translator.usesNetwork {
                switch readiness {
                case .ready, .unknown:
                    break
                case .needsDownload:
                    throw TranslationFailure.missingLanguagePack(request.providerID)
                case .unavailable:
                    throw TranslationFailure.unsupportedLanguagePair
                }
            }
            let result = try await translator.translate(request)
            quickSessionState = .completed(result)
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)
            await persistRecentTranslation(result)

            if translationSettings.autoCopyEnabled {
                await services.clipboard.writeText(result.translatedText)
            }
        } catch let failure as TranslationFailure {
            quickSessionState = .failed(failure)
            popupState = .failed(failure, originalText: quickDraft.trimmedText)
        } catch {
            let failure = TranslationFailure.providerFailed(error.localizedDescription)
            quickSessionState = .failed(failure)
            popupState = .failed(failure, originalText: quickDraft.trimmedText)
        }
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

    func selectPopupWord(_ wordTranslation: WordTranslation, at index: Int? = nil) async {
        guard case let .success(result, showsOriginal, _) = popupState else {
            return
        }

        let request = wordLookupRequest(for: wordTranslation, result: result)
        let lookupID = UUID()
        let loadingCard = TranslationPopupWordCardState(
            wordTranslation: wordTranslation,
            wordIndex: index,
            lookupState: .loading(request)
        )

        activePopupWordLookupTask?.cancel()
        activePopupWordLookupID = lookupID
        popupState = .success(result, showsOriginal: showsOriginal, wordCard: loadingCard)

        let provider = services.wordLookupProvider
        let lookupTask = Task<WordLookupState, Never> {
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

        let lookupState = await lookupTask.value
        guard activePopupWordLookupID == lookupID else {
            return
        }

        activePopupWordLookupID = nil
        activePopupWordLookupTask = nil

        guard case let .success(currentResult, currentShowsOriginal, _) = popupState,
              currentResult.id == result.id
        else {
            return
        }

        popupState = completedPopupState(
            result: currentResult,
            showsOriginal: currentShowsOriginal,
            wordTranslation: wordTranslation,
            wordIndex: index,
            lookupState: lookupState
        )
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
