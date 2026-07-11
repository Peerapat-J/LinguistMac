import Foundation
@testable import LinguistMacCore
import XCTest

final class CloudTranslationProviderTests: XCTestCase {
    func testDefaultProviderCatalogMarksCloudProvidersAsKeyRequired() {
        let descriptors = TranslationProviderCatalog.defaultDescriptors()

        XCTAssertEqual(descriptors.map(\.id), TranslationProviderID.allKnownProviders)
        XCTAssertEqual(descriptors.first { $0.id == .apple }?.configurationStatus, .ready)
        XCTAssertEqual(descriptors.first { $0.id == .deepl }?.configurationStatus, .needsAPIKey)
        XCTAssertTrue(descriptors.first { $0.id == .googleCloud }?.usesNetwork == true)
    }

    func testCloudProviderRequiresAPIKeyBeforeNetworkCall() async {
        let client = StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"translated"}]}"#))
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: InMemoryAPIKeyStore(),
            client: client
        )

        do {
            _ = try await provider.translate(request(providerID: .deepl, targetLanguage: .japanese))
            XCTFail("Expected missing API key failure.")
        } catch {
            XCTAssertEqual(error as? TranslationFailure, .missingAPIKey(.deepl))
        }

        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCloudProviderReportsUnavailableWhenAPIKeyStoreCannotBeRead() async throws {
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: UnavailableAPIKeyStore(message: "Secure store unavailable."),
            client: StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"unused"}]}"#))
        )
        let registry = DefaultTranslationProviderRegistry(providers: [provider])

        let descriptors = await registry.availableProviders()
        let deepl = try XCTUnwrap(descriptors.first { $0.id == .deepl })

        XCTAssertEqual(deepl.configurationStatus, .unavailable("Secure store unavailable."))
        XCTAssertFalse(deepl.isConfigured)
    }

    func testDeepLProviderBuildsProRequestAndDecodesResponse() async throws {
        let client = StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"sawasdee"}]}"#))
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.deepl: "test-key"]),
            client: client
        )

        let result = try await provider.translate(request(providerID: .deepl, targetLanguage: .japanese))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let body = try bodyObject(from: sentRequest) as? [String: Any]

        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(sentRequest.url.absoluteString, "https://api.deepl.com/v2/translate")
        XCTAssertEqual(sentRequest.headers["Authorization"], "DeepL-Auth-Key test-key")
        XCTAssertEqual(body?["target_lang"] as? String, "JA")
        XCTAssertEqual(body?["source_lang"] as? String, "EN")
        XCTAssertEqual(body?["text"] as? [String], ["hello"])
    }

    func testDeepLProviderUsesFreeEndpointForFreeAPIKeys() async throws {
        let client = StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"sawasdee"}]}"#))
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.deepl: "test-key:fx"]),
            client: client
        )

        let result = try await provider.translate(request(providerID: .deepl, targetLanguage: .japanese))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let body = try bodyObject(from: sentRequest) as? [String: Any]

        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(sentRequest.url.absoluteString, "https://api-free.deepl.com/v2/translate")
        XCTAssertEqual(sentRequest.headers["Authorization"], "DeepL-Auth-Key test-key:fx")
        XCTAssertEqual(body?["target_lang"] as? String, "JA")
        XCTAssertEqual(body?["source_lang"] as? String, "EN")
        XCTAssertEqual(body?["text"] as? [String], ["hello"])
    }

    func testDeepLProviderMapsBrazilianPortugueseSourceToPortuguese() async throws {
        let client = StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"konnichiwa"}]}"#))
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.deepl: "test-key"]),
            client: client
        )

        _ = try await provider.translate(
            request(
                providerID: .deepl,
                sourceLanguage: .brazilianPortuguese,
                targetLanguage: .japanese
            )
        )
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let body = try bodyObject(from: sentRequest) as? [String: Any]

        XCTAssertEqual(body?["source_lang"] as? String, "PT")
        XCTAssertEqual(body?["target_lang"] as? String, "JA")
    }

    func testDeepLProviderRejectsThaiLanguagePairsBeforeNetworkCall() async throws {
        let client = StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"unused"}]}"#))
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.deepl: "test-key"]),
            client: client
        )

        do {
            _ = try await provider.translate(request(providerID: .deepl, targetLanguage: .thai))
            XCTFail("Expected unsupported language pair failure.")
        } catch {
            XCTAssertEqual(error as? TranslationFailure, .unsupportedLanguagePair)
        }

        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testGoogleCloudProviderBuildsBodyRequestAndDecodesResponse() async throws {
        let client = StubCloudTranslationClient(
            response: jsonResponse(#"{"data":{"translations":[{"translatedText":"sawasdee"}]}}"#)
        )
        let provider = CloudTranslationProvider(
            id: .googleCloud,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.googleCloud: "test-key"]),
            client: client
        )

        let result = try await provider.translate(request(providerID: .googleCloud))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let query = queryItems(from: sentRequest.url)
        let body = try bodyObject(from: sentRequest) as? [String: String]

        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(sentRequest.url.scheme, "https")
        XCTAssertEqual(sentRequest.url.host, "translation.googleapis.com")
        XCTAssertEqual(query["key"], "test-key")
        XCTAssertNil(query["q"])
        XCTAssertNil(query["source"])
        XCTAssertNil(query["target"])
        XCTAssertNil(query["format"])
        XCTAssertEqual(body?["q"], "hello")
        XCTAssertEqual(body?["source"], "en")
        XCTAssertEqual(body?["target"], "th")
        XCTAssertEqual(body?["format"], "text")
    }

    func testMicrosoftAzureProviderBuildsRequestAndDecodesResponse() async throws {
        let client = StubCloudTranslationClient(
            response: jsonResponse(#"[{"translations":[{"text":"sawasdee","to":"th"}]}]"#)
        )
        let provider = CloudTranslationProvider(
            id: .microsoftAzure,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.microsoftAzure: "test-key"]),
            client: client
        )

        let result = try await provider.translate(request(providerID: .microsoftAzure))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let query = queryItems(from: sentRequest.url)
        let body = try bodyObject(from: sentRequest) as? [[String: String]]

        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(sentRequest.url.host, "api.cognitive.microsofttranslator.com")
        XCTAssertEqual(query["api-version"], "3.0")
        XCTAssertEqual(query["from"], "en")
        XCTAssertEqual(query["to"], "th")
        XCTAssertEqual(sentRequest.headers["Ocp-Apim-Subscription-Key"], "test-key")
        XCTAssertNil(sentRequest.headers["Ocp-Apim-Subscription-Region"])
        XCTAssertEqual(body?.first?["Text"], "hello")
    }

    func testMicrosoftAzureProviderSendsRegionHeaderWhenConfigured() async throws {
        let client = StubCloudTranslationClient(
            response: jsonResponse(#"[{"translations":[{"text":"sawasdee","to":"th"}]}]"#)
        )
        let provider = CloudTranslationProvider(
            id: .microsoftAzure,
            apiKeyStore: InMemoryAPIKeyStore(
                keys: [.microsoftAzure: "test-key"],
                regions: [.microsoftAzure: "eastus"]
            ),
            client: client
        )

        _ = try await provider.translate(request(providerID: .microsoftAzure))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)

        XCTAssertEqual(sentRequest.headers["Ocp-Apim-Subscription-Key"], "test-key")
        XCTAssertEqual(sentRequest.headers["Ocp-Apim-Subscription-Region"], "eastus")
    }

    func testMicrosoftAzureProviderAddsSupportedSourceAndTranslationReadings() async throws {
        let client = StubCloudTranslationClient(
            responses: [
                jsonResponse(#"[{"translations":[{"text":"สวัสดี","to":"th"}]}]"#),
                jsonResponse(#"[{"text":"Kon'nichiwa","script":"Latn"}]"#),
                jsonResponse(#"[{"text":"sawatdi","script":"Latn"}]"#)
            ]
        )
        let provider = CloudTranslationProvider(
            id: .microsoftAzure,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.microsoftAzure: "test-key"]),
            client: client
        )

        let result = try await provider.translate(
            request(
                providerID: .microsoftAzure,
                sourceLanguage: .japanese,
                targetLanguage: .thai
            )
        )
        let requests = await client.requests

        XCTAssertEqual(result.sourceReading, "Kon'nichiwa")
        XCTAssertEqual(result.translatedReading, "sawatdi")
        XCTAssertEqual(requests.map(\.url.path), ["/translate", "/transliterate", "/transliterate"])
        XCTAssertEqual(queryItems(from: requests[1].url)["fromScript"], "Jpan")
        XCTAssertEqual(queryItems(from: requests[2].url)["fromScript"], "Thai")
    }

    func testMicrosoftAzureProviderKeepsTranslationWhenReadingFails() async throws {
        let client = StubCloudTranslationClient(
            responses: [
                jsonResponse(#"[{"translations":[{"text":"สวัสดี","to":"th"}]}]"#),
                jsonResponse(#"{"unexpected":true}"#)
            ]
        )
        let provider = CloudTranslationProvider(
            id: .microsoftAzure,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.microsoftAzure: "test-key"]),
            client: client
        )

        let result = try await provider.translate(request(providerID: .microsoftAzure))

        XCTAssertEqual(result.translatedText, "สวัสดี")
        XCTAssertNil(result.sourceReading)
        XCTAssertNil(result.translatedReading)
    }

    func testSensitiveValueRedactorRemovesKnownSecrets() {
        let message = SensitiveValueRedactor.redact(
            "request failed with key test-key",
            secrets: ["test-key"]
        )

        XCTAssertEqual(message, "request failed with key [redacted]")
    }

    private func request(
        providerID: TranslationProviderID,
        sourceLanguage: TranslationLanguage = .english,
        targetLanguage: TranslationLanguage = .thai
    ) -> TranslationRequest {
        TranslationRequest(
            text: " hello ",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            inputMode: .quickTranslate,
            providerID: providerID
        )
    }

    private func jsonResponse(_ json: String) -> CloudTranslationHTTPResponse {
        CloudTranslationHTTPResponse(
            statusCode: 200,
            data: Data(json.utf8)
        )
    }

    private func queryItems(from url: URL) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in
                    item.value.map { (item.name, $0) }
                }
        )
    }

    private func bodyObject(from request: CloudTranslationHTTPRequest) throws -> Any {
        try JSONSerialization.jsonObject(with: XCTUnwrap(request.body))
    }
}

private struct UnavailableAPIKeyStore: APIKeyStoring {
    let message: String

    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        throw TranslationFailure.providerFailed(message)
    }

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        _ = apiKey
        _ = providerID
        throw TranslationFailure.providerFailed(message)
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        _ = providerID
        throw TranslationFailure.providerFailed(message)
    }

    func apiKeyStatus(for providerID: TranslationProviderID) async -> APIKeyStatus {
        _ = providerID
        return .unavailable(message)
    }

    func apiRegion(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        throw TranslationFailure.providerFailed(message)
    }

    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws {
        _ = apiRegion
        _ = providerID
        throw TranslationFailure.providerFailed(message)
    }

    func deleteAPIRegion(for providerID: TranslationProviderID) async throws {
        _ = providerID
        throw TranslationFailure.providerFailed(message)
    }
}
