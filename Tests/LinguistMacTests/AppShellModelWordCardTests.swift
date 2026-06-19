@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelWordCardTests: XCTestCase {
    func testSelectPopupWordLoadsCompletedWordCard() async throws {
        let wordTranslation = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let result = makeResult(
            text: "The boat reached the river bank",
            wordTranslations: [wordTranslation]
        )
        let expectedRequest = makeWordLookupRequest(for: wordTranslation, result: result)
        let lookupResult = try WordLookupResult(
            id: XCTUnwrap(UUID(uuidString: "43F8A7E5-81C0-4FAE-AE98-CF40A7E60A01")),
            request: expectedRequest,
            translatedText: "ริมฝั่งแม่น้ำ",
            definition: "The side of a river.",
            example: "The boat reached the bank.",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let expectedContent = try XCTUnwrap(
            ShownWordCardContent(
                wordTranslation: wordTranslation,
                wordIndex: 0,
                lookupResult: lookupResult
            )
        )
        let wordLookupProvider = WordCardTestLookupProvider(response: .success(lookupResult))
        let model = AppShellModel(services: makeServices(wordLookupProvider: wordLookupProvider))
        model.popupState = .success(result, showsOriginal: true)

        await model.selectPopupWord(wordTranslation, at: 0)

        let requests = await wordLookupProvider.lookupRequests()
        XCTAssertEqual(requests, [expectedRequest])
        guard case let .success(currentResult, showsOriginal, wordCard?) = model.popupState else {
            XCTFail("Expected successful popup with a word card.")
            return
        }
        XCTAssertEqual(currentResult, result.savingShownWordCard(expectedContent))
        XCTAssertTrue(showsOriginal)
        XCTAssertEqual(wordCard.wordTranslation, wordTranslation)
        XCTAssertEqual(wordCard.wordIndex, 0)
        XCTAssertEqual(wordCard.lookupState, .completed(lookupResult))
    }

    func testCompletedPopupWordCardPersistsDisplayReadyContentInHistory() async throws {
        let wordTranslation = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let result = makeResult(
            text: "The boat reached the river bank",
            wordTranslations: [wordTranslation]
        )
        let expectedRequest = makeWordLookupRequest(for: wordTranslation, result: result)
        let lookupResult = WordLookupResult(
            request: expectedRequest,
            translatedText: "ริมฝั่งแม่น้ำ",
            definition: "The side of a river.",
            example: "The boat reached the bank."
        )
        let expectedContent = try XCTUnwrap(
            ShownWordCardContent(
                wordTranslation: wordTranslation,
                wordIndex: 0,
                lookupResult: lookupResult
            )
        )
        let historyStore = WordCardTestTranslationHistoryStore()
        let wordLookupProvider = WordCardTestLookupProvider(response: .success(lookupResult))
        let model = AppShellModel(
            services: makeServices(
                wordLookupProvider: wordLookupProvider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(result, showsOriginal: false)

        await model.selectPopupWord(wordTranslation, at: 0)

        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults.map(\.id), [result.id])
        XCTAssertEqual(savedResults.first?.shownWordCards, [expectedContent])
        XCTAssertEqual(model.recentTranslations.first?.shownWordCards, [expectedContent])
    }

    func testSelectPopupWordShowsEmptyCardWithoutFailingTranslation() async throws {
        let wordTranslation = WordTranslation(sourceText: "hello", translatedText: "สวัสดี")
        let result = makeResult(text: "hello friend", wordTranslations: [wordTranslation])
        let expectedRequest = makeWordLookupRequest(for: wordTranslation, result: result)
        let historyStore = WordCardTestTranslationHistoryStore()
        let wordLookupProvider = WordCardTestLookupProvider(response: .empty)
        let model = AppShellModel(
            services: makeServices(
                wordLookupProvider: wordLookupProvider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(result, showsOriginal: false)

        await model.selectPopupWord(wordTranslation)

        XCTAssertEqual(model.popupState.copyableText, result.translatedText)
        XCTAssertFalse(model.popupState.showsOriginal)
        XCTAssertEqual(model.popupState.wordCard?.lookupState, .empty(expectedRequest))
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults, [])
    }

    func testSelectPopupWordShowsFailureCardWithoutFailingTranslation() async throws {
        let wordTranslation = WordTranslation(sourceText: "offline", translatedText: "ออฟไลน์")
        let result = makeResult(text: "offline mode", wordTranslations: [wordTranslation])
        let historyStore = WordCardTestTranslationHistoryStore()
        let wordLookupProvider = WordCardTestLookupProvider(response: .failure(.missingLanguagePack(.apple)))
        let model = AppShellModel(
            services: makeServices(
                wordLookupProvider: wordLookupProvider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(result, showsOriginal: false)

        await model.selectPopupWord(wordTranslation)

        XCTAssertEqual(model.popupState.copyableText, result.translatedText)
        XCTAssertFalse(model.popupState.showsOriginal)
        XCTAssertEqual(model.popupState.wordCard?.wordTranslation, wordTranslation)
        XCTAssertEqual(model.popupState.wordCard?.lookupState, .failed(.missingLanguagePack(.apple)))
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults, [])
    }

    func testCancelledPopupWordLookupDoesNotPersistHistory() async throws {
        let wordTranslation = WordTranslation(sourceText: "cancel", translatedText: "ยกเลิก")
        let result = makeResult(text: "cancel lookup", wordTranslations: [wordTranslation])
        let historyStore = WordCardTestTranslationHistoryStore()
        let wordLookupProvider = WordCardTestLookupProvider(response: .failure(.cancelled))
        let model = AppShellModel(
            services: makeServices(
                wordLookupProvider: wordLookupProvider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(result, showsOriginal: false)

        await model.selectPopupWord(wordTranslation)

        XCTAssertEqual(model.popupState.wordCard?.lookupState, .failed(.cancelled))
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults, [])
    }

    func testSelectPopupWordRestoresSavedCardWithoutRunningLookup() async {
        let wordTranslation = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let savedContent = ShownWordCardContent(
            wordTranslation: wordTranslation,
            wordIndex: 0,
            translatedText: "ริมฝั่งแม่น้ำ",
            sentenceContext: "The boat reached the river bank.",
            definition: "The side of a river.",
            example: "The boat reached the bank."
        )
        let result = makeResult(
            text: "The boat reached the river bank",
            wordTranslations: [wordTranslation]
        ).savingShownWordCard(savedContent)
        let wordLookupProvider = WordCardTestLookupProvider(response: .failure(.providerFailed))
        let model = AppShellModel(services: makeServices(wordLookupProvider: wordLookupProvider))
        model.popupState = .success(result, showsOriginal: false)

        await model.selectPopupWord(wordTranslation, at: 0)

        let requests = await wordLookupProvider.lookupRequests()
        XCTAssertEqual(requests, [])
        guard case let .completed(lookupResult) = model.popupState.wordCard?.lookupState else {
            XCTFail("Expected restored completed lookup state.")
            return
        }
        XCTAssertEqual(lookupResult.translatedText, savedContent.translatedText)
        XCTAssertEqual(lookupResult.sentenceContextDisplayText, savedContent.sentenceContext)
        XCTAssertEqual(lookupResult.definition, savedContent.definition)
        XCTAssertEqual(lookupResult.example, savedContent.example)
    }

    func testSelectPopupWordSavesRestoredCardAsNewestHistoryCard() async throws {
        let firstWord = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let secondWord = WordTranslation(sourceText: "boat", translatedText: "เรือ")
        let firstContent = ShownWordCardContent(
            wordTranslation: firstWord,
            wordIndex: 0,
            translatedText: "ธนาคาร",
            sentenceContext: "The boat reached the bank."
        )
        let secondContent = ShownWordCardContent(
            wordTranslation: secondWord,
            wordIndex: 1,
            translatedText: "เรือ",
            sentenceContext: "The boat reached the bank."
        )
        let result = makeResult(
            text: "The boat reached the bank",
            wordTranslations: [firstWord, secondWord]
        )
        .savingShownWordCard(secondContent)
        .savingShownWordCard(firstContent)
        let historyStore = WordCardTestTranslationHistoryStore(results: [result])
        let wordLookupProvider = WordCardTestLookupProvider(response: .failure(.providerFailed))
        let model = AppShellModel(
            recentTranslations: [result],
            services: makeServices(
                wordLookupProvider: wordLookupProvider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(result, showsOriginal: true)
        model.activePopupWordLookupID = UUID()
        model.activePopupWordLookupTask = Task { .failed(.cancelled) }

        await model.selectPopupWord(secondWord, at: 1)

        let expectedResult = result.savingShownWordCard(secondContent)
        let requests = await wordLookupProvider.lookupRequests()
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.recentTranslations.first?.shownWordCards, expectedResult.shownWordCards)
        XCTAssertEqual(savedResults.first?.shownWordCards, expectedResult.shownWordCards)
        guard case let .success(currentResult, showsOriginal, wordCard?) = model.popupState else {
            XCTFail("Expected successful popup with a restored word card.")
            return
        }
        XCTAssertTrue(showsOriginal)
        XCTAssertEqual(currentResult.shownWordCards, expectedResult.shownWordCards)
        XCTAssertEqual(wordCard.wordTranslation, secondWord)
        XCTAssertEqual(wordCard.wordIndex, 1)
        XCTAssertNil(model.activePopupWordLookupID)
        XCTAssertNil(model.activePopupWordLookupTask)
    }

    func testDismissPopupWordCardPreservesTranslationResult() {
        let wordTranslation = WordTranslation(sourceText: "hello", translatedText: "สวัสดี")
        let result = makeResult(text: "hello friend", wordTranslations: [wordTranslation])
        let request = makeWordLookupRequest(for: wordTranslation, result: result)
        let wordCard = TranslationPopupWordCardState(
            wordTranslation: wordTranslation,
            lookupState: .loading(request)
        )
        let model = AppShellModel(services: makeServices())
        model.popupState = .success(result, showsOriginal: true, wordCard: wordCard)

        model.dismissPopupWordCard()

        XCTAssertEqual(model.popupState.copyableText, result.translatedText)
        XCTAssertTrue(model.popupState.showsOriginal)
        XCTAssertNil(model.popupState.wordCard)
    }

    private func makeServices(
        wordLookupProvider: any WordLookupProviding = UnavailableWordLookupProvider(),
        historyStore: any TranslationHistoryStoring = WordCardTestTranslationHistoryStore()
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: WordCardTestScreenCaptureService(),
            ocr: WordCardTestOCRService(),
            translatorRegistry: WordCardTestTranslationProviderRegistry(),
            languageAvailability: WordCardTestLanguageAvailabilityChecker(),
            settingsStore: WordCardTestAppSettingsStore(),
            apiKeyStore: WordCardTestAPIKeyStore(),
            launchAtLogin: WordCardTestLaunchAtLoginService(),
            historyStore: historyStore,
            permissionChecker: WordCardTestPermissionChecker(),
            clipboard: WordCardTestClipboard(),
            selectedTextCapture: WordCardTestSelectedTextCapture(),
            shortcutRegistry: WordCardTestShortcutRegistry(),
            wordLookupProvider: wordLookupProvider
        )
    }

    private func makeResult(
        text: String,
        translatedText: String? = nil,
        wordTranslations: [WordTranslation]
    ) -> TranslationResult {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .selectedText,
            providerID: .apple
        )
        return TranslationResult(
            request: request,
            translatedText: translatedText ?? text + " (translated)",
            wordTranslations: wordTranslations,
            createdAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeWordLookupRequest(
        for wordTranslation: WordTranslation,
        result: TranslationResult
    ) -> WordLookupRequest {
        WordLookupRequest(
            sourceText: wordTranslation.sourceText,
            sentenceContext: result.originalText,
            sourceLanguage: result.request.sourceLanguage,
            targetLanguage: result.request.targetLanguage,
            providerID: result.request.providerID,
            inputMode: result.request.inputMode
        )
    }
}

private enum WordCardTestLookupResponse {
    case success(WordLookupResult)
    case empty
    case failure(WordLookupFailure)
}

private actor WordCardTestLookupProvider: WordLookupProviding {
    private let response: WordCardTestLookupResponse
    private var requests: [WordLookupRequest]

    init(response: WordCardTestLookupResponse) {
        self.response = response
        requests = []
    }

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        requests.append(request)
        switch response {
        case let .success(result):
            return result
        case .empty:
            return nil
        case let .failure(failure):
            throw failure
        }
    }

    func lookupRequests() -> [WordLookupRequest] {
        requests
    }
}

private struct WordCardTestScreenCaptureService: ScreenCaptureServicing {
    func captureSelection() async throws -> CapturedScreenRegion {
        CapturedScreenRegion(imageData: Data())
    }
}

private struct WordCardTestOCRService: OCRServicing {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText {
        _ = region
        return RecognizedText(text: "hello")
    }
}

private struct WordCardTestTranslationProviderRegistry: TranslationProviderRegistry {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        _ = id
        throw TranslationFailure.providerUnavailable(.apple)
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        [
            TranslationProviderDescriptor(
                id: .apple,
                displayName: "Apple Translation",
                requiresAPIKey: false,
                usesNetwork: false
            )
        ]
    }
}

private struct WordCardTestLanguageAvailabilityChecker: LanguageAvailabilityChecking {
    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        _ = source
        _ = target
        _ = sampleText
        return .ready
    }
}

private actor WordCardTestAppSettingsStore: AppSettingsStoring {
    func loadSettings() async throws -> AppSettings {
        AppSettings()
    }

    func saveSettings(_ settings: AppSettings) async throws {
        _ = settings
    }
}

private actor WordCardTestAPIKeyStore: APIKeyStoring {
    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        return nil
    }

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        _ = apiKey
        _ = providerID
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        _ = providerID
    }

    func apiKeyStatus(for providerID: TranslationProviderID) async -> APIKeyStatus {
        _ = providerID
        return .missing
    }

    func apiRegion(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        return nil
    }

    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws {
        _ = apiRegion
        _ = providerID
    }

    func deleteAPIRegion(for providerID: TranslationProviderID) async throws {
        _ = providerID
    }
}

private actor WordCardTestLaunchAtLoginService: LaunchAtLoginServicing {
    func isEnabled() async -> Bool {
        false
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        _ = isEnabled
    }
}

private actor WordCardTestTranslationHistoryStore: TranslationHistoryStoring {
    private var results: [TranslationResult]

    init(results: [TranslationResult] = []) {
        self.results = results
    }

    func save(_ result: TranslationResult) async throws {
        results = TranslationHistoryPolicy.inserting(result, into: results)
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        TranslationHistoryPolicy.trimmed(results, limit: limit)
    }
}

private struct WordCardTestPermissionChecker: PermissionChecking {
    func status(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }
}

private actor WordCardTestClipboard: ClipboardServicing {
    func readText() async -> String? {
        nil
    }

    func writeText(_ text: String) async {
        _ = text
    }
}

private struct WordCardTestSelectedTextCapture: SelectedTextCapturing {
    func captureSelectedText() async throws -> String {
        "hello"
    }
}

private actor WordCardTestShortcutRegistry: ShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        _ = shortcut
        _ = action
    }

    func unregister(_ action: ShortcutAction) async {
        _ = action
    }
}
