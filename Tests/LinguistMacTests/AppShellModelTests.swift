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
    }

    func testRefreshRecentTranslationsUsesHistoryStoreLimit() async {
        let first = makeResult(text: "first", createdAt: Date(timeIntervalSince1970: 1))
        let second = makeResult(text: "second", createdAt: Date(timeIntervalSince1970: 2))
        let historyStore = TestTranslationHistoryStore(results: [first, second])
        let model = AppShellModel(services: makeServices(historyStore: historyStore))

        await model.refreshRecentTranslations(limit: 1)

        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["second"])
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
        clipboard: TestClipboard = TestClipboard()
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: TestScreenCaptureService(),
            ocr: TestOCRService(),
            translatorRegistry: TestTranslationProviderRegistry(),
            languageAvailability: TestLanguageAvailabilityChecker(),
            settingsStore: TestAppSettingsStore(),
            apiKeyStore: TestAPIKeyStore(),
            launchAtLogin: TestLaunchAtLoginService(),
            historyStore: historyStore,
            permissionChecker: TestPermissionChecker(),
            clipboard: clipboard,
            selectedTextCapture: TestSelectedTextCapture(),
            shortcutRegistry: TestShortcutRegistry()
        )
    }

    private func makeResult(
        text: String,
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
            request: request,
            translatedText: text,
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
