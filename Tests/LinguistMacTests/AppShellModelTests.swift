@testable import LinguistMac
@testable import LinguistMacCore
import SwiftData
import XCTest

@MainActor
final class AppShellModelTests: XCTestCase {
    func testSwiftDataHistoryStoreDeduplicatesSavedResultID() async throws {
        let id = UUID()
        let (store, _) = try makeSwiftDataHistoryStore(trimLimit: 10)
        let original = makeResult(id: id, text: "original", createdAt: Date(timeIntervalSince1970: 1))
        let wordTranslations = [
            WordTranslation(sourceText: "hello", translatedText: "สวัสดี"),
            WordTranslation(sourceText: "world", translatedText: "โลก")
        ]
        let updated = makeResult(
            id: id,
            text: "updated",
            wordTranslations: wordTranslations,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try await store.save(original)
        try await store.save(updated)

        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent, [updated])
        XCTAssertEqual(recent.first?.wordTranslations, wordTranslations)
    }

    func testSwiftDataHistoryStoreTrimsAllOverflowRows() async throws {
        let (store, container) = try makeSwiftDataHistoryStore(trimLimit: 3)
        let existing = (0 ..< 40).map { index in
            makeResult(text: "old-\(index)", createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        let context = ModelContext(container)
        for result in existing {
            context.insert(TranslationHistoryRecord(result: result))
        }
        try context.save()
        let newest = makeResult(text: "newest", createdAt: Date(timeIntervalSince1970: 100))

        try await store.save(newest)

        let recent = try await store.recent(limit: 100)
        XCTAssertEqual(recent, [newest, existing[39], existing[38]])
    }

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
        historyStore: any TranslationHistoryStoring = TestTranslationHistoryStore(),
        apiKeyStore: any APIKeyStoring = TestAPIKeyStore(),
        clipboard: TestClipboard = TestClipboard()
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: TestScreenCaptureService(),
            ocr: TestOCRService(),
            translatorRegistry: TestTranslationProviderRegistry(),
            languageAvailability: TestLanguageAvailabilityChecker(),
            settingsStore: TestAppSettingsStore(),
            apiKeyStore: apiKeyStore,
            launchAtLogin: TestLaunchAtLoginService(),
            historyStore: historyStore,
            permissionChecker: TestPermissionChecker(),
            clipboard: clipboard,
            selectedTextCapture: TestSelectedTextCapture(),
            shortcutRegistry: TestShortcutRegistry()
        )
    }

    private func makeSwiftDataHistoryStore(
        trimLimit: Int
    ) throws -> (SwiftDataTranslationHistoryStore, ModelContainer) {
        let configuration = ModelConfiguration(
            "TestHistory-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: TranslationHistoryRecord.self,
            configurations: configuration
        )
        return (
            SwiftDataTranslationHistoryStore(container: container, trimLimit: trimLimit),
            container
        )
    }

    private func makeResult(
        id: UUID = UUID(),
        text: String,
        wordTranslations: [WordTranslation] = [],
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
            createdAt: createdAt
        )
    }
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

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(
            request: request,
            translatedText: "สวัสดี"
        )
    }
}

private struct TestTranslationProviderRegistry: TranslationProviderRegistry {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        guard id == .apple else {
            throw TranslationFailure.providerUnavailable(id)
        }

        return TestTranslationProvider()
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
    func status(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
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
