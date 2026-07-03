@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelTests: XCTestCase {
    func testQuickTranslatePersistsHistoryAndAutocopiesResult() async throws {
        let historyStore = TestTranslationHistoryStore()
        let clipboard = TestClipboard()
        let model = AppShellModel(
            settings: AppSettings(
                sourceLanguage: .english,
                targetLanguage: .thai,
                autoCopyEnabled: true
            ),
            services: makeServices(
                historyStore: historyStore,
                clipboard: clipboard
            )
        )
        model.quickDraft.sourceText = "  hello  "

        await model.runQuickTranslate()

        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["สวัสดี"])
        XCTAssertEqual(model.popupState.copyableText, "สวัสดี")
        let copiedText = await clipboard.textValue()
        XCTAssertEqual(copiedText, "สวัสดี")

        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults.map(\.translatedText), ["สวัสดี"])
        XCTAssertEqual(savedResults.first?.request.text, "hello")
        XCTAssertNil(model.historyLoadError)
    }

    func testQuickTranslateAddsWordBreakdownForCompletedSentences() async throws {
        let historyStore = TestTranslationHistoryStore()
        let provider = TestTranslationProvider(
            translatedTextsBySource: [
                "hello world": "สวัสดีชาวโลก",
                "hello": "สวัสดี",
                "world": "โลก"
            ]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeServices(
                translatorRegistry: TestTranslationProviderRegistry(provider: provider),
                historyStore: historyStore
            )
        )
        model.quickDraft.sourceText = "  hello world  "

        await model.runQuickTranslate()
        await model.activeQuickWordTranslationTask?.value

        let expectedWords = [
            WordTranslation(sourceText: "hello", translatedText: "สวัสดี"),
            WordTranslation(sourceText: "world", translatedText: "โลก")
        ]
        guard case let .completed(result) = model.quickSessionState else {
            return XCTFail("Expected completed quick translate state.")
        }
        XCTAssertEqual(result.translatedText, "สวัสดีชาวโลก")
        XCTAssertEqual(result.wordTranslations, expectedWords)
        XCTAssertEqual(model.popupState, .success(result, showsOriginal: false))

        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults.first?.wordTranslations, expectedWords)
    }

    func testQuickTranslatePublishesSentenceBeforeWordBreakdownFinishes() async throws {
        let historyStore = TestTranslationHistoryStore()
        let clipboard = TestClipboard()
        let provider = GatedQuickTranslateProvider()
        let model = AppShellModel(
            settings: AppSettings(
                sourceLanguage: .english,
                targetLanguage: .thai,
                autoCopyEnabled: true
            ),
            services: makeServices(
                translatorRegistry: TestTranslationProviderRegistry(provider: provider),
                historyStore: historyStore,
                clipboard: clipboard
            )
        )
        model.quickDraft.sourceText = "hello world"
        let quickTranslateReturned = expectation(description: "Quick Translate returns before word lookups finish")

        let runTask = Task {
            await model.runQuickTranslate()
            quickTranslateReturned.fulfill()
        }
        await fulfillment(of: [quickTranslateReturned], timeout: 1)

        guard case let .completed(immediateResult) = model.quickSessionState else {
            await provider.releaseWordTranslations()
            await runTask.value
            return XCTFail("Expected the sentence result before word lookup enrichment.")
        }
        XCTAssertEqual(immediateResult.translatedText, "สวัสดีชาวโลก")
        XCTAssertEqual(immediateResult.wordTranslations, [])
        let immediateClipboardText = await clipboard.textValue()
        XCTAssertEqual(immediateClipboardText, "สวัสดีชาวโลก")
        let immediateHistory = try await historyStore.recent(limit: 10)
        XCTAssertEqual(immediateHistory.first?.wordTranslations, [])

        await provider.releaseWordTranslations()
        await model.activeQuickWordTranslationTask?.value
        await runTask.value

        let expectedWords = [
            WordTranslation(sourceText: "hello", translatedText: "สวัสดี"),
            WordTranslation(sourceText: "world", translatedText: "โลก")
        ]
        guard case let .completed(enrichedResult) = model.quickSessionState else {
            return XCTFail("Expected enriched quick translate state.")
        }
        XCTAssertEqual(enrichedResult.wordTranslations, expectedWords)
        let enrichedHistory = try await historyStore.recent(limit: 10)
        XCTAssertEqual(enrichedHistory.first?.wordTranslations, expectedWords)
    }

    func testQuickTranslateSurfacesHistorySaveFailure() async {
        let model = AppShellModel(
            services: makeServices(historyStore: FailingSaveTestTranslationHistoryStore())
        )
        model.quickDraft.sourceText = "hello"

        await model.runQuickTranslate()

        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["สวัสดี"])
        XCTAssertEqual(model.popupState.copyableText, "สวัสดี")
        XCTAssertEqual(
            model.historyLoadError?.message,
            "Translation history could not be saved. Recent translations may be missing after relaunch."
        )
        XCTAssertEqual(model.historyLoadError?.diagnosticDescription, "disk write failed")
    }

    func testScreenTranslateSurfacesHistorySaveFailure() async {
        let model = AppShellModel(
            services: makeServices(historyStore: FailingSaveTestTranslationHistoryStore())
        )

        await model.runScreenTranslation()

        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["สวัสดี"])
        XCTAssertEqual(model.popupState.copyableText, "สวัสดี")
        XCTAssertEqual(
            model.historyLoadError?.message,
            "Translation history could not be saved. Recent translations may be missing after relaunch."
        )
        XCTAssertEqual(model.historyLoadError?.diagnosticDescription, "disk write failed")
    }

    func testRefreshRecentTranslationsUsesHistoryStoreLimit() async {
        let first = makeResult(text: "first", createdAt: Date(timeIntervalSince1970: 1))
        let second = makeResult(text: "second", createdAt: Date(timeIntervalSince1970: 2))
        let historyStore = TestTranslationHistoryStore(results: [first, second])
        let model = AppShellModel(services: makeServices(historyStore: historyStore))
        model.historyLoadError = HistoryLoadErrorState(
            message: "Previous failure",
            diagnosticDescription: "previous diagnostic"
        )

        await model.refreshRecentTranslations(limit: 1)

        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["second"])
        XCTAssertNil(model.historyLoadError)
    }

    func testRefreshRecentTranslationsSurfacesHistoryLoadFailure() async {
        let existing = makeResult(text: "existing", createdAt: Date(timeIntervalSince1970: 1))
        let model = AppShellModel(
            recentTranslations: [existing],
            services: makeServices(historyStore: FailingTestTranslationHistoryStore())
        )

        await model.refreshRecentTranslations()

        XCTAssertEqual(model.recentTranslations, [existing])
        XCTAssertEqual(
            model.historyLoadError?.message,
            "Translation history could not be loaded. Try again or restart LinguistMac."
        )
        XCTAssertEqual(
            model.historyLoadError?.diagnosticDescription,
            "The translation provider could not complete the request. Check configuration or try again."
        )
        XCTAssertFalse(model.historyLoadError?.diagnosticDescription.contains("database unavailable") == true)
    }

    func testLiveServicesSurfaceHistoryInitializationFailure() async {
        let services = LiveLinguistServices.make(
            historyStoreFactory: {
                throw TestHistoryInitializationError()
            }
        )
        let model = AppShellModel(services: services)

        await model.refreshRecentTranslations()

        XCTAssertEqual(
            model.historyLoadError?.diagnosticDescription,
            "Translation history storage is unavailable. disk unavailable"
        )
        XCTAssertEqual(model.recentTranslations, [])
    }

    func testRefreshReadinessIncludesVoicePermissionStatuses() async {
        let statuses: [PermissionKind: PermissionStatus] = [
            .screenRecording: .granted,
            .accessibility: .granted,
            .microphone: .denied,
            .speechRecognition: .restricted
        ]
        let model = AppShellModel(services: makeServices(permissionChecker: TestPermissionChecker(statuses: statuses)))

        await model.refreshReadiness()

        let items = Dictionary(uniqueKeysWithValues: model.readiness.items.map { ($0.kind, $0) })
        XCTAssertEqual(items[.voiceMicrophone]?.status, .denied)
        XCTAssertEqual(items[.speechRecognition]?.status, .restricted)
        XCTAssertTrue(model.readiness.isScreenTranslationReady)
    }

    func testTestAPIKeyConfigurationPreservesUnsavedAzureRegionDraft() async {
        let model = AppShellModel(
            services: makeServices(
                apiKeyStore: TestAPIKeyStore(
                    status: .present,
                    apiRegion: "saved-region"
                )
            )
        )
        model.providerAPIRegionDrafts[.microsoftAzure] = "unsaved-region"

        await model.testAPIKeyConfiguration(for: .microsoftAzure)

        XCTAssertEqual(model.providerAPIRegionDrafts[.microsoftAzure], "unsaved-region")
        XCTAssertEqual(
            model.providerConfigurationMessages[.microsoftAzure],
            "API key and region are present. Translation requests can use this provider."
        )
    }

    func testShowHistoryResultReopensSuccessfulPopup() {
        let result = makeResult(text: "from history")
        let model = AppShellModel(services: makeServices())

        model.showHistoryResult(result)

        XCTAssertEqual(model.lastCommand, .history)
        XCTAssertEqual(model.popupState, .success(result, showsOriginal: false))
    }

    func testShowHistoryResultRestoresShownWordCard() {
        let wordTranslation = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let shownWordCard = ShownWordCardContent(
            wordTranslation: wordTranslation,
            wordIndex: 0,
            translatedText: "ริมฝั่งแม่น้ำ",
            sentenceContext: "The boat reached the river bank.",
            definition: "The side of a river.",
            example: "The boat reached the bank."
        )
        let result = makeResult(
            text: "The boat reached the river bank.",
            wordTranslations: [wordTranslation],
            shownWordCards: [shownWordCard]
        )
        let model = AppShellModel(services: makeServices())

        model.showHistoryResult(result)

        XCTAssertEqual(model.lastCommand, .history)
        guard case let .success(currentResult, showsOriginal, wordCard?) = model.popupState else {
            XCTFail("Expected successful popup with restored word card.")
            return
        }
        XCTAssertEqual(currentResult, result)
        XCTAssertFalse(showsOriginal)
        XCTAssertEqual(wordCard.wordTranslation, wordTranslation)
        XCTAssertEqual(wordCard.wordIndex, 0)
        guard case let .completed(lookupResult) = wordCard.lookupState else {
            XCTFail("Expected restored completed lookup state.")
            return
        }
        XCTAssertEqual(lookupResult.translatedText, shownWordCard.translatedText)
        XCTAssertEqual(lookupResult.sentenceContextDisplayText, shownWordCard.sentenceContext)
        XCTAssertEqual(lookupResult.definition, shownWordCard.definition)
        XCTAssertEqual(lookupResult.example, shownWordCard.example)
    }

    func testRememberPopupWindowFrameClampsPersistedSize() {
        let model = AppShellModel(services: makeServices())

        model.rememberPopupWindowFrame(CGRect(x: 12, y: 24, width: 900, height: 120))

        XCTAssertEqual(model.settings.popupOriginX, 12)
        XCTAssertEqual(model.settings.popupOriginY, 24)
        XCTAssertEqual(model.settings.popupWidth, 720)
        XCTAssertEqual(model.settings.popupHeight, 240)
        XCTAssertEqual(
            model.savedPopupWindowFrame,
            CGRect(x: 12, y: 24, width: 720, height: 240)
        )
    }

    private func makeServices(
        translatorRegistry: (any TranslationProviderRegistry)? = nil,
        historyStore: any TranslationHistoryStoring = TestTranslationHistoryStore(),
        apiKeyStore: any APIKeyStoring = TestAPIKeyStore(),
        permissionChecker: any PermissionChecking = TestPermissionChecker(),
        clipboard: TestClipboard = TestClipboard(),
        soundPlayer: any ScreenTranslationSoundPlaying = NoOpScreenTranslationSoundPlayer(),
        notifier: any ScreenTranslationNotificationPosting = NoOpScreenTranslationNotifier()
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: TestScreenCaptureService(),
            ocr: TestOCRService(),
            translatorRegistry: translatorRegistry ?? TestTranslationProviderRegistry(),
            languageAvailability: TestLanguageAvailabilityChecker(),
            settingsStore: TestAppSettingsStore(),
            apiKeyStore: apiKeyStore,
            launchAtLogin: TestLaunchAtLoginService(),
            historyStore: historyStore,
            permissionChecker: permissionChecker,
            clipboard: clipboard,
            selectedTextCapture: TestSelectedTextCapture(),
            shortcutRegistry: TestShortcutRegistry(),
            screenTranslationSoundPlayer: soundPlayer,
            screenTranslationNotifier: notifier
        )
    }
}

private func makeResult(
    id: UUID = UUID(),
    text: String,
    wordTranslations: [WordTranslation] = [],
    shownWordCards: [ShownWordCardContent] = [],
    createdAt: Date = Date(timeIntervalSince1970: 1)
) -> TranslationResult {
    let request = TranslationRequest(
        text: text,
        sourceLanguage: .english,
        targetLanguage: .thai,
        inputMode: .quickTranslate,
        providerID: .apple
    )
    return TranslationResult(
        id: id,
        request: request,
        translatedText: text,
        wordTranslations: wordTranslations,
        shownWordCards: shownWordCards,
        createdAt: createdAt
    )
}

private struct TestScreenCaptureService: ScreenCaptureServicing {
    func captureSelection() async throws -> CapturedScreenRegion {
        CapturedScreenRegion(imageData: Data())
    }
}

private struct TestOCRService: OCRServicing {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText {
        _ = region
        return RecognizedText(text: "hello")
    }
}

private struct TestTranslationProvider: TranslationProviding {
    let id = TranslationProviderID.apple
    let displayName = "Apple Translation"
    let detail = "Test provider"
    let requiresAPIKey = false
    let usesNetwork = false
    let privacySummary = "On-device"
    let translatedText: String
    let translatedTextsBySource: [String: String]

    init(
        translatedText: String = "สวัสดี",
        translatedTextsBySource: [String: String] = [:]
    ) {
        self.translatedText = translatedText
        self.translatedTextsBySource = translatedTextsBySource
    }

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(
            request: request,
            translatedText: translatedTextsBySource[request.text] ?? translatedText
        )
    }
}

private struct TestTranslationProviderRegistry: TranslationProviderRegistry {
    let provider: any TranslationProviding

    init(provider: any TranslationProviding = TestTranslationProvider()) {
        self.provider = provider
    }

    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        guard id == .apple else {
            throw TranslationFailure.providerUnavailable(id)
        }

        return provider
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        [
            TranslationProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                requiresAPIKey: provider.requiresAPIKey,
                usesNetwork: provider.usesNetwork
            )
        ]
    }
}

private actor GatedQuickTranslateProvider: TranslationProviding {
    nonisolated let id = TranslationProviderID.apple
    nonisolated let displayName = "Apple Translation"
    nonisolated let detail = "Gated test provider"
    nonisolated let requiresAPIKey = false
    nonisolated let usesNetwork = true
    nonisolated let privacySummary = "Test cloud provider"

    private var isWordTranslationReleased = false
    private var wordTranslationContinuations: [CheckedContinuation<Void, Never>] = []

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        if request.text != "hello world" {
            await waitForWordTranslationRelease()
        }

        return TranslationResult(
            request: request,
            translatedText: translatedText(for: request.text)
        )
    }

    func releaseWordTranslations() {
        isWordTranslationReleased = true
        let continuations = wordTranslationContinuations
        wordTranslationContinuations = []
        continuations.forEach { $0.resume() }
    }

    private func waitForWordTranslationRelease() async {
        guard !isWordTranslationReleased else {
            return
        }

        await withCheckedContinuation { continuation in
            wordTranslationContinuations.append(continuation)
        }
    }

    private func translatedText(for text: String) -> String {
        switch text {
        case "hello world":
            "สวัสดีชาวโลก"
        case "hello":
            "สวัสดี"
        case "world":
            "โลก"
        default:
            text
        }
    }
}

private struct TestLanguageAvailabilityChecker: LanguageAvailabilityChecking {
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

private actor TestAppSettingsStore: AppSettingsStoring {
    private var settings = AppSettings()

    func loadSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}

private actor TestAPIKeyStore: APIKeyStoring {
    private var status: APIKeyStatus
    private var regions: [TranslationProviderID: String]

    init(status: APIKeyStatus = .missing, apiRegion: String? = nil) {
        self.status = status
        regions = apiRegion.map { [.microsoftAzure: $0] } ?? [:]
    }

    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        return nil
    }

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        _ = apiKey
        _ = providerID
        status = .present
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        _ = providerID
        status = .missing
    }

    func apiKeyStatus(for providerID: TranslationProviderID) async -> APIKeyStatus {
        _ = providerID
        return status
    }

    func apiRegion(for providerID: TranslationProviderID) async throws -> String? {
        regions[providerID]
    }

    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws {
        regions[providerID] = apiRegion
    }

    func deleteAPIRegion(for providerID: TranslationProviderID) async throws {
        regions[providerID] = nil
    }
}

private actor TestLaunchAtLoginService: LaunchAtLoginServicing {
    func isEnabled() async -> Bool {
        false
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        _ = isEnabled
    }
}

private actor TestTranslationHistoryStore: TranslationHistoryStoring {
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

private struct FailingTestTranslationHistoryStore: TranslationHistoryStoring {
    func save(_ result: TranslationResult) async throws {
        _ = result
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        _ = limit
        throw TranslationFailure.providerFailed("database unavailable")
    }
}

private struct FailingSaveTestTranslationHistoryStore: TranslationHistoryStoring {
    func save(_ result: TranslationResult) async throws {
        _ = result
        throw TestHistorySaveError()
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        _ = limit
        return []
    }
}

private struct TestHistoryInitializationError: LocalizedError {
    var errorDescription: String? {
        "disk unavailable"
    }
}

private struct TestHistorySaveError: LocalizedError {
    var errorDescription: String? {
        "disk write failed"
    }
}

private struct TestPermissionChecker: PermissionChecking {
    var statuses: [PermissionKind: PermissionStatus] = [:]
    var requestStatuses: [PermissionKind: PermissionStatus] = [:]

    func status(for kind: PermissionKind) async -> PermissionStatus {
        statuses[kind] ?? .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        requestStatuses[kind] ?? statuses[kind] ?? .granted
    }
}

private actor TestClipboard: ClipboardServicing {
    private var text: String?

    func readText() async -> String? {
        text
    }

    func writeText(_ text: String) async {
        self.text = text
    }

    func textValue() -> String? {
        text
    }
}

private struct TestSelectedTextCapture: SelectedTextCapturing {
    func captureSelectedText() async throws -> String {
        "hello"
    }
}

private actor TestShortcutRegistry: ShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        _ = shortcut
        _ = action
    }

    func unregister(_ action: ShortcutAction) async {
        _ = action
    }
}
