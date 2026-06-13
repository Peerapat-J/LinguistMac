import Foundation

public actor InputModeTranslationCoordinator {
    public private(set) var state: TranslationSessionState
    private var stateHistory: [TranslationSessionState]
    private let services: LinguistServices

    public init(services: LinguistServices) {
        self.services = services
        state = .idle
        stateHistory = [.idle]
    }

    public func states() -> [TranslationSessionState] {
        stateHistory
    }

    @discardableResult
    public func translateSelectedText(settings: AppSettings) async -> TranslationSessionState {
        guard await requestPermissionIfNeeded(.accessibility) == .granted else {
            return fail(with: .permissionDenied(.accessibility))
        }

        do {
            setState(.capturing)
            let sourceText = try await services.selectedTextCapture.captureSelectedText()
            return await translate(
                sourceText,
                inputMode: .selectedText,
                recognizedLanguage: nil,
                settings: settings
            )
        } catch {
            return fail(with: failure(from: error))
        }
    }

    @discardableResult
    public func translateClipboardDoubleCopy(settings: AppSettings) async -> TranslationSessionState {
        guard settings.doubleCopyTranslationEnabled else {
            return fail(with: .inputModeDisabled(.clipboardDoubleCopy))
        }
        guard await requestPermissionIfNeeded(.accessibility) == .granted else {
            return fail(with: .permissionDenied(.accessibility))
        }
        guard let sourceText = await services.clipboard.readText() else {
            return fail(with: .emptyInput)
        }

        return await translate(
            sourceText,
            inputMode: .clipboardDoubleCopy,
            recognizedLanguage: nil,
            settings: settings
        )
    }

    @discardableResult
    public func translateDragSelection(settings: AppSettings) async -> TranslationSessionState {
        guard settings.dragTranslationEnabled else {
            return fail(with: .inputModeDisabled(.dragTranslation))
        }
        guard await requestPermissionIfNeeded(.accessibility) == .granted else {
            return fail(with: .permissionDenied(.accessibility))
        }
        guard await requestPermissionIfNeeded(.screenRecording) == .granted else {
            return fail(with: .permissionDenied(.screenRecording))
        }

        do {
            setState(.capturing)
            let region = try await services.screenCapture.captureSelection()
            setState(.recognizing)
            let recognizedText = try await services.ocr.recognizeText(in: region)
            return await translate(
                recognizedText.text,
                inputMode: .dragTranslation,
                recognizedLanguage: recognizedText.language,
                settings: settings
            )
        } catch {
            return fail(with: failure(from: error))
        }
    }

    private func translate(
        _ rawSourceText: String,
        inputMode: TranslationInputMode,
        recognizedLanguage: TranslationLanguage?,
        settings: AppSettings
    ) async -> TranslationSessionState {
        let sourceText = rawSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            return fail(with: .emptyInput)
        }

        let sourceLanguage = SourceLanguageResolver.resolvedSourceLanguage(
            settingsSource: settings.sourceLanguage,
            sourceText: sourceText,
            recognizedLanguage: recognizedLanguage
        )
        let providerID = await services.translatorRegistry.supportedProviderID(
            preferred: settings.selectedProviderID,
            sourceLanguage: sourceLanguage,
            targetLanguage: settings.targetLanguage
        )
        let request = TranslationRequest(
            text: sourceText,
            sourceLanguage: sourceLanguage,
            targetLanguage: settings.targetLanguage,
            inputMode: inputMode,
            providerID: providerID
        )

        do {
            let provider = try await services.translatorRegistry.provider(for: request.providerID)
            setState(.translating(request))
            if !provider.usesNetwork {
                let readiness = await services.languageAvailability.readiness(
                    from: request.sourceLanguage,
                    to: request.targetLanguage,
                    sampleText: request.text
                )
                switch readiness {
                case .ready, .unknown:
                    break
                case .needsDownload:
                    return fail(with: .missingLanguagePack(request.providerID))
                case .unavailable:
                    return fail(with: .unsupportedLanguagePair)
                }
            }

            let result = try await provider.translate(request)
            await saveHistoryIfPossible(result)

            if settings.autoCopyEnabled {
                await services.clipboard.writeText(result.translatedText)
            }

            setState(.completed(result))
            return state
        } catch {
            return fail(with: failure(from: error))
        }
    }

    private func requestPermissionIfNeeded(_ kind: PermissionKind) async -> PermissionStatus {
        let status = await services.permissionChecker.status(for: kind)
        guard status != .granted else {
            return status
        }

        setState(.requestingPermission(kind))
        return await services.permissionChecker.request(for: kind)
    }

    private func saveHistoryIfPossible(_ result: TranslationResult) async {
        do {
            try await services.historyStore.save(result)
        } catch {
            // History persistence is best-effort; translation success remains authoritative.
        }
    }

    private func failure(from error: Error) -> TranslationFailure {
        if let failure = error as? TranslationFailure {
            return failure
        }

        return .providerFailed(error.localizedDescription)
    }

    private func fail(with failure: TranslationFailure) -> TranslationSessionState {
        setState(.failed(failure))
        return state
    }

    private func setState(_ newState: TranslationSessionState) {
        state = newState
        stateHistory.append(newState)
    }
}
