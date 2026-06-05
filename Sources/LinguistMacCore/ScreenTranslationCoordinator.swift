import Foundation

public actor ScreenTranslationCoordinator {
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
    public func translateScreenSelection(settings: AppSettings) async -> TranslationSessionState {
        let permissionStatus = await services.permissionChecker.status(for: .screenRecording)
        guard permissionStatus == .granted else {
            setState(.requestingPermission(.screenRecording))
            return fail(with: .permissionDenied(.screenRecording))
        }

        do {
            setState(.capturing)
            let region = try await services.screenCapture.captureSelection()

            setState(.recognizing)
            let recognizedText = try await services.ocr.recognizeText(in: region)
            let sourceText = recognizedText.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceText.isEmpty else {
                return fail(with: .noTextRecognized)
            }

            let sourceLanguage = resolvedSourceLanguage(
                settingsSource: settings.sourceLanguage,
                recognizedLanguage: recognizedText.language
            )
            let request = TranslationRequest(
                text: sourceText,
                sourceLanguage: sourceLanguage,
                targetLanguage: settings.targetLanguage,
                inputMode: .screenSelection,
                providerID: settings.selectedProviderID
            )

            setState(.translating(request))
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

            let provider = try await services.translatorRegistry.provider(for: request.providerID)
            let result = try await provider.translate(request)
            try await services.historyStore.save(result)

            if settings.autoCopyEnabled {
                await services.clipboard.writeText(result.translatedText)
            }

            setState(.completed(result))
            return state
        } catch {
            return fail(with: failure(from: error))
        }
    }

    private func resolvedSourceLanguage(
        settingsSource: TranslationLanguage,
        recognizedLanguage: TranslationLanguage?
    ) -> TranslationLanguage {
        guard settingsSource.supportsAutoDetect else {
            return settingsSource
        }

        return recognizedLanguage ?? settingsSource
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
