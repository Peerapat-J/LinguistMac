import Foundation

public struct CloudTranslationHTTPRequest: Equatable, Sendable {
    public let providerID: TranslationProviderID
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(
        providerID: TranslationProviderID,
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data? = nil
    ) {
        self.providerID = providerID
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct CloudTranslationHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public enum TranslationProviderCatalog {
    public static let defaultProviderOrder: [TranslationProviderID] = TranslationProviderID.allKnownProviders

    public static func defaultDescriptors(
        configuredProviderIDs: Set<TranslationProviderID> = []
    ) -> [TranslationProviderDescriptor] {
        defaultProviderOrder.compactMap {
            descriptor(
                for: $0,
                configurationStatus: configurationStatus(for: $0, configuredProviderIDs: configuredProviderIDs)
            )
        }
    }

    public static func descriptor(
        for id: TranslationProviderID,
        configurationStatus: TranslationProviderConfigurationStatus? = nil
    ) -> TranslationProviderDescriptor? {
        switch id {
        case .apple:
            TranslationProviderDescriptor(
                id: .apple,
                displayName: "Apple Translation",
                requiresAPIKey: false,
                usesNetwork: false,
                detail: "On-device system translation is the default engine.",
                configurationStatus: configurationStatus ?? .ready,
                privacySummary: "Text stays on device when Apple Translation handles the request."
            )
        case .deepl:
            cloudDescriptor(
                id: .deepl,
                displayName: "DeepL",
                detail: "Bring your own DeepL API key for cloud translation.",
                configurationStatus: configurationStatus
            )
        case .googleCloud:
            cloudDescriptor(
                id: .googleCloud,
                displayName: "Google Cloud Translation",
                detail: "Bring your own Google Cloud Translation API key.",
                configurationStatus: configurationStatus
            )
        case .microsoftAzure:
            cloudDescriptor(
                id: .microsoftAzure,
                displayName: "Microsoft Azure Translator",
                detail: "Bring your own Azure Translator key and region.",
                configurationStatus: configurationStatus
            )
        default:
            nil
        }
    }

    private static func cloudDescriptor(
        id: TranslationProviderID,
        displayName: String,
        detail: String,
        configurationStatus: TranslationProviderConfigurationStatus?
    ) -> TranslationProviderDescriptor {
        TranslationProviderDescriptor(
            id: id,
            displayName: displayName,
            requiresAPIKey: true,
            usesNetwork: true,
            detail: detail,
            configurationStatus: configurationStatus ?? .needsAPIKey,
            privacySummary: "Selected text is sent to this provider only when this engine is selected."
        )
    }

    private static func configurationStatus(
        for id: TranslationProviderID,
        configuredProviderIDs: Set<TranslationProviderID>
    ) -> TranslationProviderConfigurationStatus {
        TranslationProviderID.cloudProviders.contains(id) && !configuredProviderIDs.contains(id)
            ? .needsAPIKey
            : .ready
    }
}

public struct DefaultTranslationProviderRegistry: TranslationProviderRegistry {
    private let providers: [TranslationProviderID: any TranslationProviding]

    public init(providers: [any TranslationProviding]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        guard let provider = providers[id] else {
            throw TranslationFailure.providerUnavailable(id)
        }

        return provider
    }

    public func availableProviders() async -> [TranslationProviderDescriptor] {
        var descriptors: [TranslationProviderDescriptor] = []
        for provider in providers.values {
            let status = await provider.configurationStatus()
            descriptors.append(
                TranslationProviderDescriptor(
                    id: provider.id,
                    displayName: provider.displayName,
                    requiresAPIKey: provider.requiresAPIKey,
                    usesNetwork: provider.usesNetwork,
                    detail: provider.detail,
                    configurationStatus: status,
                    privacySummary: provider.privacySummary
                )
            )
        }

        return descriptors.sorted {
            providerSortIndex($0.id) < providerSortIndex($1.id)
        }
    }

    private func providerSortIndex(_ id: TranslationProviderID) -> Int {
        TranslationProviderCatalog.defaultProviderOrder.firstIndex(of: id) ?? Int.max
    }
}

public struct CloudTranslationProvider: TranslationProviding {
    public let id: TranslationProviderID
    public let displayName: String
    public let detail: String
    public let requiresAPIKey = true
    public let usesNetwork = true
    public let privacySummary: String

    private let apiKeyStore: any APIKeyStoring
    private let client: any CloudTranslationClient

    public init(
        id: TranslationProviderID,
        apiKeyStore: any APIKeyStoring,
        client: any CloudTranslationClient
    ) {
        self.id = id
        let descriptor = TranslationProviderCatalog.descriptor(for: id)
        displayName = descriptor?.displayName ?? id.rawValue
        detail = descriptor?.detail ?? "Bring your own API key for cloud translation."
        privacySummary = descriptor?.privacySummary ?? "Selected text is sent to this provider when selected."
        self.apiKeyStore = apiKeyStore
        self.client = client
    }

    public func configurationStatus() async -> TranslationProviderConfigurationStatus {
        switch await apiKeyStore.apiKeyStatus(for: id) {
        case .present:
            .ready
        case .missing:
            .needsAPIKey
        case let .unavailable(reason):
            .unavailable(reason)
        }
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranslationFailure.emptyInput
        }
        guard let apiKey = try await apiKeyStore.apiKey(for: id), !apiKey.isEmpty else {
            throw TranslationFailure.missingAPIKey(id)
        }
        guard id.supports(sourceLanguage: request.sourceLanguage, targetLanguage: request.targetLanguage) else {
            throw TranslationFailure.unsupportedLanguagePair
        }
        let apiRegion = try await apiKeyStore.apiRegion(for: id)

        let httpRequest = try makeHTTPRequest(for: request, text: text, apiKey: apiKey, apiRegion: apiRegion)
        let response = try await client.perform(httpRequest)
        let translatedText = try decodeTranslatedText(from: response)

        return TranslationResult(
            request: TranslationRequest(
                text: text,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage,
                inputMode: request.inputMode,
                providerID: request.providerID
            ),
            translatedText: translatedText
        )
    }

    private func makeHTTPRequest(
        for request: TranslationRequest,
        text: String,
        apiKey: String,
        apiRegion: String?
    ) throws -> CloudTranslationHTTPRequest {
        switch id {
        case .deepl:
            return try makeDeepLRequest(for: request, text: text, apiKey: apiKey)
        case .googleCloud:
            return try makeGoogleCloudRequest(for: request, text: text, apiKey: apiKey)
        case .microsoftAzure:
            return try makeMicrosoftAzureRequest(for: request, text: text, apiKey: apiKey, apiRegion: apiRegion)
        default:
            throw TranslationFailure.providerUnavailable(id)
        }
    }

    private func makeDeepLRequest(
        for request: TranslationRequest,
        text: String,
        apiKey: String
    ) throws -> CloudTranslationHTTPRequest {
        let host = apiKey.isDeepLFreeAPIKey ? "api-free.deepl.com" : "api.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else {
            throw TranslationFailure.providerUnavailable(id)
        }

        var body = DeepLTranslateRequest(
            text: [text],
            targetLang: request.targetLanguage.deeplLanguageCode
        )
        body.sourceLang = request.sourceLanguage.supportsAutoDetect ? nil : request.sourceLanguage.deeplLanguageCode

        return try CloudTranslationHTTPRequest(
            providerID: id,
            url: url,
            headers: [
                "Authorization": "DeepL-Auth-Key \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: JSONEncoder().encode(body)
        )
    }

    private func makeGoogleCloudRequest(
        for request: TranslationRequest,
        text: String,
        apiKey: String
    ) throws -> CloudTranslationHTTPRequest {
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components?.url else {
            throw TranslationFailure.providerUnavailable(id)
        }

        var body = GoogleCloudTranslateRequest(
            text: text,
            target: request.targetLanguage.id,
            format: "text"
        )
        body.source = request.sourceLanguage.supportsAutoDetect ? nil : request.sourceLanguage.id

        return try CloudTranslationHTTPRequest(
            providerID: id,
            url: url,
            headers: ["Content-Type": "application/json"],
            body: JSONEncoder().encode(body)
        )
    }

    private func makeMicrosoftAzureRequest(
        for request: TranslationRequest,
        text: String,
        apiKey: String,
        apiRegion: String?
    ) throws -> CloudTranslationHTTPRequest {
        var components = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")
        var queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: request.targetLanguage.id)
        ]
        if !request.sourceLanguage.supportsAutoDetect {
            queryItems.append(URLQueryItem(name: "from", value: request.sourceLanguage.id))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw TranslationFailure.providerUnavailable(id)
        }

        let body = [MicrosoftAzureTranslateRequest(text: text)]
        var headers = [
            "Ocp-Apim-Subscription-Key": apiKey,
            "Content-Type": "application/json; charset=UTF-8"
        ]
        if let apiRegion = apiRegion?.trimmedNonEmpty {
            headers["Ocp-Apim-Subscription-Region"] = apiRegion
        }

        return try CloudTranslationHTTPRequest(
            providerID: id,
            url: url,
            headers: headers,
            body: JSONEncoder().encode(body)
        )
    }

    private func decodeTranslatedText(from response: CloudTranslationHTTPResponse) throws -> String {
        switch id {
        case .deepl:
            let decoded = try JSONDecoder().decode(DeepLTranslateResponse.self, from: response.data)
            guard let text = decoded.translations.first?.text else {
                throw TranslationFailure.providerFailed("DeepL returned no translation.")
            }
            return text
        case .googleCloud:
            let decoded = try JSONDecoder().decode(GoogleCloudTranslateResponse.self, from: response.data)
            guard let text = decoded.data.translations.first?.translatedText else {
                throw TranslationFailure.providerFailed("Google Cloud returned no translation.")
            }
            return text
        case .microsoftAzure:
            let decoded = try JSONDecoder().decode([MicrosoftAzureTranslateResponse].self, from: response.data)
            guard let text = decoded.first?.translations.first?.text else {
                throw TranslationFailure.providerFailed("Microsoft Azure returned no translation.")
            }
            return text
        default:
            throw TranslationFailure.providerUnavailable(id)
        }
    }
}

public enum SensitiveValueRedactor {
    public static let placeholder = "[redacted]"

    public static func redact(_ text: String, secrets: [String]) -> String {
        secrets
            .filter { !$0.isEmpty }
            .reduce(text) { partialResult, secret in
                partialResult.replacingOccurrences(of: secret, with: placeholder)
            }
    }
}

private struct DeepLTranslateRequest: Encodable {
    let text: [String]
    let targetLang: String
    var sourceLang: String?

    enum CodingKeys: String, CodingKey {
        case text
        case targetLang = "target_lang"
        case sourceLang = "source_lang"
    }
}

private struct DeepLTranslateResponse: Decodable {
    struct Translation: Decodable {
        let text: String
    }

    let translations: [Translation]
}

private struct GoogleCloudTranslateResponse: Decodable {
    struct Payload: Decodable {
        let translations: [Translation]
    }

    struct Translation: Decodable {
        let translatedText: String
    }

    let data: Payload
}

private struct GoogleCloudTranslateRequest: Encodable {
    let text: String
    let target: String
    let format: String
    var source: String?

    enum CodingKeys: String, CodingKey {
        case text = "q"
        case target
        case format
        case source
    }
}

private struct MicrosoftAzureTranslateRequest: Encodable {
    let text: String

    enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}

private struct MicrosoftAzureTranslateResponse: Decodable {
    struct Translation: Decodable {
        let text: String
    }

    let translations: [Translation]
}

private extension TranslationLanguage {
    var deeplLanguageCode: String {
        switch id {
        case "zh-Hans":
            "ZH-HANS"
        default:
            id.uppercased()
        }
    }
}

private extension String {
    var isDeepLFreeAPIKey: Bool {
        trimmedNonEmpty?.lowercased().hasSuffix(":fx") == true
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
