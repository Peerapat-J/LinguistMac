@testable import LinguistMacCore
import XCTest

final class TranslationModelsTests: XCTestCase {
    func testTranslationResultUsesRequestTextAsOriginalByDefault() {
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )

        let result = TranslationResult(request: request, translatedText: "sawasdee")

        XCTAssertEqual(result.originalText, "hello")
        XCTAssertEqual(result.request, request)
    }

    func testProviderDescriptorDistinguishesOnDeviceAndCloudProviders() {
        let apple = TranslationProviderDescriptor(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false
        )
        let deepl = TranslationProviderDescriptor(
            id: .deepl,
            displayName: "DeepL",
            requiresAPIKey: true,
            usesNetwork: true
        )

        XCTAssertFalse(apple.requiresAPIKey)
        XCTAssertFalse(apple.usesNetwork)
        XCTAssertTrue(deepl.requiresAPIKey)
        XCTAssertTrue(deepl.usesNetwork)
    }

    func testSessionStateCanRepresentPermissionAndProviderFailures() {
        let permissionState = TranslationSessionState.failed(
            .permissionDenied(.screenRecording)
        )
        let providerState = TranslationSessionState.failed(
            .missingAPIKey(.deepl)
        )

        XCTAssertNotEqual(permissionState, providerState)
    }

    func testTranslationRequestResolvesAutoDetectedSourceFromText() {
        let request = TranslationRequest(
            text: "This is a simple English sentence for language detection.",
            sourceLanguage: .autoDetect,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )

        let resolvedRequest = request.resolvingAutoDetectedSource()

        XCTAssertEqual(resolvedRequest.sourceLanguage, .english)
        XCTAssertEqual(resolvedRequest.targetLanguage, .thai)
        XCTAssertEqual(resolvedRequest.text, request.text)
    }
}
