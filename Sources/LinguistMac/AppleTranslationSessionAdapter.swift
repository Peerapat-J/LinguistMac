import Foundation
import LinguistMacCore
import Translation

enum AppleTranslationSessionAdapter {
    static func prepareLanguagePack(
        source: Locale.Language,
        target: Locale.Language
    ) async throws {
        #if compiler(>=6.3)
            guard #available(macOS 26.0, *) else {
                throw TranslationFailure.providerUnavailable(.apple)
            }

            try await prepareWithAppleSession(source: source, target: target)
        #else
            _ = source
            _ = target
            throw TranslationFailure.providerUnavailable(.apple)
        #endif
    }

    static func translate(
        _ request: TranslationRequest,
        source: Locale.Language,
        target: Locale.Language,
        text: String
    ) async throws -> TranslationResult {
        #if compiler(>=6.3)
            guard #available(macOS 26.0, *) else {
                throw TranslationFailure.providerUnavailable(.apple)
            }

            return try await translateWithAppleSession(request, source: source, target: target, text: text)
        #else
            _ = request
            _ = source
            _ = target
            _ = text
            throw TranslationFailure.providerUnavailable(.apple)
        #endif
    }

    static func translationFailure(from error: Error) -> TranslationFailure {
        #if compiler(>=6.3)
            mapAppleTranslationError(error)
        #else
            .providerFailed(error.localizedDescription)
        #endif
    }

    #if compiler(>=6.3)
        @available(macOS 26.0, *)
        private static func prepareWithAppleSession(
            source: Locale.Language,
            target: Locale.Language
        ) async throws {
            do {
                let session = TranslationSession(installedSource: source, target: target)
                try await session.prepareTranslation()
            } catch {
                throw mapAppleTranslationError(error)
            }
        }

        @available(macOS 26.0, *)
        private static func translateWithAppleSession(
            _ request: TranslationRequest,
            source: Locale.Language,
            target: Locale.Language,
            text: String
        ) async throws -> TranslationResult {
            do {
                let session = TranslationSession(installedSource: source, target: target)
                try await session.prepareTranslation()
                let response = try await session.translate(text)
                return TranslationResult(
                    request: request,
                    translatedText: response.targetText,
                    originalText: response.sourceText
                )
            } catch {
                throw mapAppleTranslationError(error)
            }
        }

        private static func mapAppleTranslationError(_ error: Error) -> TranslationFailure {
            let isUnsupportedLanguageError =
                TranslationError.unsupportedSourceLanguage ~= error ||
                TranslationError.unsupportedTargetLanguage ~= error ||
                TranslationError.unsupportedLanguagePairing ~= error

            if isUnsupportedLanguageError {
                return .unsupportedLanguagePair
            }
            if TranslationError.unableToIdentifyLanguage ~= error {
                return .providerFailed("Apple Translation could not identify the source language.")
            }
            if TranslationError.nothingToTranslate ~= error {
                return .emptyInput
            }
            if #available(macOS 26.0, *), TranslationError.notInstalled ~= error {
                return .missingLanguagePack(.apple)
            }

            return .providerFailed(error.localizedDescription)
        }
    #endif
}
