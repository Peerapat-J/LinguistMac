@testable import LinguistMacCore
import XCTest

final class TranslationModelsTests: XCTestCase {
    func testInputModeDisplayNamesAreUserFacing() {
        let displayNames: [TranslationInputMode: String] = [
            .screenSelection: "Screen Translate",
            .selectedText: "Selected Text",
            .clipboardDoubleCopy: "Cmd+C+C",
            .dragTranslation: "Drag Translation",
            .quickTranslate: "Quick Translate"
        ]

        for (inputMode, displayName) in displayNames {
            XCTAssertEqual(inputMode.displayName, displayName)
            XCTAssertNotEqual(inputMode.displayName, inputMode.rawValue)
        }
    }

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
        XCTAssertEqual(result.wordTranslations, [])
    }

    func testWordTranslationTokenizerKeepsWordTokensOnly() {
        let words = WordTranslationTokenizer.words(in: " Hello, world! 123. ")

        XCTAssertEqual(words, ["Hello", "world", "123"])
    }

    func testWordLookupResultRoundTripsDisplayReadyContent() throws {
        let id = try XCTUnwrap(UUID(uuidString: "19F55810-1B34-4E19-8892-BD23E10C6D38"))
        let request = WordLookupRequest(
            sourceText: "hello",
            sentenceContext: "hello world",
            sourceLanguage: .english,
            targetLanguage: .thai,
            providerID: .apple
        )
        let result = WordLookupResult(
            id: id,
            request: request,
            translatedText: "สวัสดี",
            definition: "A greeting.",
            example: "Hello world.",
            createdAt: Date(timeIntervalSince1970: 10)
        )

        let data = try JSONEncoder().encode(result)
        let decodedResult = try JSONDecoder().decode(WordLookupResult.self, from: data)

        XCTAssertEqual(decodedResult, result)
        XCTAssertEqual(decodedResult.request.sourceText, "hello")
        XCTAssertEqual(decodedResult.translatedText, "สวัสดี")
    }

    func testWordLookupResultProvidesTrimmedSentenceContextForDisplay() {
        let request = WordLookupRequest(
            sourceText: "bank",
            sentenceContext: "  The canoe reached the river bank.  ",
            sourceLanguage: .english,
            targetLanguage: .thai,
            providerID: .apple
        )
        let result = WordLookupResult(request: request, translatedText: "ริมฝั่ง")

        XCTAssertEqual(result.sentenceContextDisplayText, "The canoe reached the river bank.")
    }

    func testWordLookupResultOmitsBlankSentenceContextForDisplay() {
        let request = WordLookupRequest(
            sourceText: "bank",
            sentenceContext: " ",
            sourceLanguage: .english,
            targetLanguage: .thai,
            providerID: .apple
        )
        let result = WordLookupResult(request: request, translatedText: "ริมฝั่ง")

        XCTAssertNil(result.sentenceContextDisplayText)
    }

    func testWordLookupStateRepresentsEmptyAndFailureSeparately() {
        let request = WordLookupRequest(
            sourceText: "hello",
            sentenceContext: "hello world",
            sourceLanguage: .english,
            targetLanguage: .thai,
            providerID: .apple
        )

        XCTAssertNotEqual(
            WordLookupState.empty(request),
            .failed(.providerFailed)
        )
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

    func testProviderLanguageSupportExcludesDeepLThaiPairs() {
        XCTAssertFalse(
            TranslationProviderID.deepl.supports(sourceLanguage: .english, targetLanguage: .thai)
        )
        XCTAssertFalse(
            TranslationProviderID.deepl.supports(sourceLanguage: .thai, targetLanguage: .english)
        )
        XCTAssertTrue(
            TranslationProviderID.deepl.supports(sourceLanguage: .english, targetLanguage: .japanese)
        )
        XCTAssertTrue(
            TranslationProviderID.googleCloud.supports(sourceLanguage: .english, targetLanguage: .thai)
        )
    }

    func testProviderIDKnownProviderRejectsUnknownRawValues() {
        XCTAssertEqual(TranslationProviderID.knownProvider(rawValue: "deepl"), .deepl)
        XCTAssertNil(TranslationProviderID.knownProvider(rawValue: "stale-provider"))
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

    func testSourceLanguageResolverUsesRecognizedLanguageBeforeTextDetection() {
        let resolvedLanguage = SourceLanguageResolver.resolvedSourceLanguage(
            settingsSource: .autoDetect,
            sourceText: "This English text should not override OCR metadata.",
            recognizedLanguage: .japanese
        )

        XCTAssertEqual(resolvedLanguage, .japanese)
    }

    func testSourceLanguageResolverKeepsManualSourceLanguage() {
        let resolvedLanguage = SourceLanguageResolver.resolvedSourceLanguage(
            settingsSource: .thai,
            sourceText: "This is a simple English sentence for language detection.",
            recognizedLanguage: .english
        )

        XCTAssertEqual(resolvedLanguage, .thai)
    }
}
