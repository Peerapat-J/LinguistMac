import Foundation
import LinguistMacCore

@MainActor
extension AppShellModel {
    func runScreenTranslation() async {
        record(.screenTranslate)
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
