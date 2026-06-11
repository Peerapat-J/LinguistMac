import Foundation
import LinguistMacCore
import Translation

struct AppleTranslationProvider: TranslationProviding {
    let id: TranslationProviderID = .apple
    let displayName = "Apple Translation"
    let detail = "On-device system translation is the default engine."
    let requiresAPIKey = false
    let usesNetwork = false
    let privacySummary = "Text stays on device when Apple Translation handles the request."

    func isConfigured() async -> Bool {
        true
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranslationFailure.emptyInput
        }
        let resolvedRequest = request.resolvingAutoDetectedSource()
        guard let source = resolvedRequest.sourceLanguage.localeLanguage,
              let target = resolvedRequest.targetLanguage.localeLanguage
        else {
            throw TranslationFailure.providerFailed("Apple Translation needs a resolved source and target language.")
        }

        guard #available(macOS 26.0, *) else {
            throw TranslationFailure.providerUnavailable(.apple)
        }

        return try await AppleTranslationSessionAdapter.translate(
            resolvedRequest,
            source: source,
            target: target,
            text: text
        )
    }
}

struct AppleTranslationAvailabilityService: LanguageAvailabilityChecking {
    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        guard let targetLanguage = target.localeLanguage else {
            return .unavailable
        }

        let availability = LanguageAvailability()
        let trimmedSampleText = sampleText?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let status: LanguageAvailability.Status
            if let sourceLanguage = source.localeLanguage {
                status = await availability.status(from: sourceLanguage, to: targetLanguage)
            } else if let trimmedSampleText, !trimmedSampleText.isEmpty {
                status = try await availability.status(for: trimmedSampleText, to: targetLanguage)
            } else {
                return .unknown
            }

            return readiness(from: status)
        } catch {
            return .unavailable
        }
    }

    private func readiness(from status: LanguageAvailability.Status) -> LanguagePackReadiness {
        switch status {
        case .installed:
            .ready
        case .supported:
            .needsDownload
        case .unsupported:
            .unavailable
        @unknown default:
            .unknown
        }
    }
}

extension TranslationLanguage {
    var localeLanguage: Locale.Language? {
        guard !supportsAutoDetect else {
            return nil
        }

        return Locale.Language(identifier: id)
    }

    // swiftlint:disable:next unused_declaration superfluous_disable_command
    static func fromLocaleLanguage(_ language: Locale.Language) -> TranslationLanguage? {
        TranslationLanguageCatalog.language(forID: language.minimalIdentifier)
    }
}
