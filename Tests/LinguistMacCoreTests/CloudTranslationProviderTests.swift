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
            _ = try await provider.translate(request(providerID: .deepl))
            XCTFail("Expected missing API key failure.")
        } catch {
            XCTAssertEqual(error as? TranslationFailure, .missingAPIKey(.deepl))
        }

        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDeepLProviderBuildsProRequestAndDecodesResponse() async throws {
        let client = StubCloudTranslationClient(response: jsonResponse(#"{"translations":[{"text":"sawasdee"}]}"#))
        let provider = CloudTranslationProvider(
            id: .deepl,
            apiKeyStore: InMemoryAPIKeyStore(keys: [.deepl: "test-key"]),
            client: client
        )

        let result = try await provider.translate(request(providerID: .deepl))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let body = try bodyObject(from: sentRequest) as? [String: Any]

        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(sentRequest.url.absoluteString, "https://api.deepl.com/v2/translate")
        XCTAssertEqual(sentRequest.headers["Authorization"], "DeepL-Auth-Key test-key")
        XCTAssertEqual(body?["target_lang"] as? String, "TH")
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

        let result = try await provider.translate(request(providerID: .deepl))
        let requests = await client.requests
        let sentRequest = try XCTUnwrap(requests.first)
        let body = try bodyObject(from: sentRequest) as? [String: Any]

        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(sentRequest.url.absoluteString, "https://api-free.deepl.com/v2/translate")
        XCTAssertEqual(sentRequest.headers["Authorization"], "DeepL-Auth-Key test-key:fx")
        XCTAssertEqual(body?["target_lang"] as? String, "TH")
        XCTAssertEqual(body?["source_lang"] as? String, "EN")
        XCTAssertEqual(body?["text"] as? [String], ["hello"])
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
        XCTAssertEqual(body?.first?["Text"], "hello")
    }

    func testSensitiveValueRedactorRemovesKnownSecrets() {
        let message = SensitiveValueRedactor.redact(
            "request failed with key test-key",
            secrets: ["test-key"]
        )

        XCTAssertEqual(message, "request failed with key [redacted]")
    }

    private func request(providerID: TranslationProviderID) -> TranslationRequest {
        TranslationRequest(
            text: " hello ",
            sourceLanguage: .english,
            targetLanguage: .thai,
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
