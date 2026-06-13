import Foundation

public actor InputModeTranslationCoordinator {
    private static let maximumWordTranslationCount = 32

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
            if let readinessFailure = await languageReadinessFailure(
                for: request,
                provider: provider
            ) {
                return fail(with: readinessFailure)
            }

            let result = try await provider.translate(request)
            let completedResult = await resultWithWordTranslationsIfNeeded(
                result,
                provider: provider
            )
            await saveHistoryIfPossible(completedResult)

            if settings.autoCopyEnabled {
                await services.clipboard.writeText(completedResult.translatedText)
            }

            setState(.completed(completedResult))
            return state
        } catch {
            return fail(with: failure(from: error))
        }
    }

    private func languageReadinessFailure(
        for request: TranslationRequest,
        provider: any TranslationProviding
    ) async -> TranslationFailure? {
        guard !provider.usesNetwork else {
            return nil
        }

        let readiness = await services.languageAvailability.readiness(
            from: request.sourceLanguage,
            to: request.targetLanguage,
            sampleText: request.text
        )
        switch readiness {
        case .ready, .unknown:
            return nil
        case .needsDownload:
            return .missingLanguagePack(request.providerID)
        case .unavailable:
            return .unsupportedLanguagePair
        }
    }

    private func resultWithWordTranslationsIfNeeded(
        _ result: TranslationResult,
        provider: any TranslationProviding
    ) async -> TranslationResult {
        guard result.request.inputMode == .selectedText else {
            return result
        }

        let sourceWords = WordTranslationTokenizer.words(in: result.originalText)
        guard sourceWords.count > 1,
              sourceWords.count <= Self.maximumWordTranslationCount
        else {
            return result
        }

        // The sentence translation is still the primary result if additive word lookups fail.
        guard let wordTranslations = try? await wordTranslations(
            for: sourceWords,
            request: result.request,
            provider: provider
        ) else {
            return result
        }

        return TranslationResult(
            id: result.id,
            request: result.request,
            translatedText: result.translatedText,
            originalText: result.originalText,
            wordTranslations: wordTranslations,
            createdAt: result.createdAt
        )
    }

    private func wordTranslations(
        for sourceWords: [String],
        request: TranslationRequest,
        provider: any TranslationProviding
    ) async throws -> [WordTranslation] {
        var translatedBySource: [String: String] = [:]
        var translations: [WordTranslation] = []

        for sourceWord in sourceWords {
            let translatedText: String
            if let cachedTranslation = translatedBySource[sourceWord] {
                translatedText = cachedTranslation
            } else {
                let wordRequest = TranslationRequest(
                    text: sourceWord,
                    sourceLanguage: request.sourceLanguage,
                    targetLanguage: request.targetLanguage,
                    inputMode: request.inputMode,
                    providerID: request.providerID
                )
                translatedText = try await provider.translate(wordRequest).translatedText
                translatedBySource[sourceWord] = translatedText
            }

            translations.append(
                WordTranslation(
                    sourceText: sourceWord,
                    translatedText: translatedText
                )
            )
        }

        return translations
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
