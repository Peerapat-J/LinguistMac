import Foundation
import LinguistMacCore
import Translation

struct DefaultTranslationProviderRegistry: TranslationProviderRegistry {
    private let providers: [TranslationProviderID: any TranslationProviding]

    init(providers: [any TranslationProviding] = [AppleTranslationProvider()]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        guard let provider = providers[id] else {
            throw TranslationFailure.providerUnavailable(id)
        }

        return provider
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        providers.values
            .map {
                TranslationProviderDescriptor(
                    id: $0.id,
                    displayName: $0.displayName,
                    requiresAPIKey: $0.requiresAPIKey,
                    usesNetwork: $0.usesNetwork
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}

struct AppleTranslationProvider: TranslationProviding {
    let id: TranslationProviderID = .apple
    let displayName = "Apple Translation"
    let requiresAPIKey = false
    let usesNetwork = false

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranslationFailure.emptyInput
        }
        guard let source = request.sourceLanguage.localeLanguage,
              let target = request.targetLanguage.localeLanguage
        else {
            throw TranslationFailure.providerFailed("Apple Translation needs a resolved source and target language.")
        }

        guard #available(macOS 26.0, *) else {
            throw TranslationFailure.providerUnavailable(.apple)
        }

        return try await AppleTranslationSessionAdapter.translate(
            request,
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

    static func fromLocaleLanguage(_ language: Locale.Language) -> TranslationLanguage? {
        TranslationLanguageCatalog.language(forID: language.minimalIdentifier)
    }
}
