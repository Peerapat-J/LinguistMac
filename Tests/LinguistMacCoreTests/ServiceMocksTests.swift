@testable import LinguistMacCore
import Foundation
import XCTest

final class ServiceMocksTests: XCTestCase {
    func testServicesCanDriveMockTranslationFlow() async throws {
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .screenSelection,
            providerID: .apple
        )
        let region = CapturedScreenRegion(imageData: Data([1, 2, 3]))
        let provider = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "sawasdee"
        )
        let services = LinguistServices(
            screenCapture: StubScreenCaptureService(result: .success(region)),
            ocr: StubOCRService(result: .success(RecognizedText(text: request.text, language: .english))),
            translatorRegistry: StubTranslationProviderRegistry(provider: provider),
            settingsStore: InMemoryAppSettingsStore(),
            historyStore: InMemoryTranslationHistoryStore(),
            permissionChecker: StubPermissionChecker(statuses: [.screenRecording: .granted]),
            clipboard: InMemoryClipboard(),
            shortcutRegistry: RecordingShortcutRegistry()
        )

        let capturedRegion = try await services.screenCapture.captureSelection()
        let recognizedText = try await services.ocr.recognizeText(in: capturedRegion)
        let translator = try await services.translatorRegistry.provider(for: request.providerID)
        let result = try await translator.translate(request)

        XCTAssertEqual(capturedRegion, region)
        XCTAssertEqual(recognizedText.text, "hello")
        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(result.originalText, "hello")
    }

    func testInMemoryStoresSupportSettingsHistoryClipboardAndShortcuts() async throws {
        let settingsStore = InMemoryAppSettingsStore()
        var settings = try await settingsStore.loadSettings()
        settings.autoCopyEnabled = true
        try await settingsStore.saveSettings(settings)

        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )
        let result = TranslationResult(request: request, translatedText: "sawasdee")
        let historyStore = InMemoryTranslationHistoryStore()
        try await historyStore.save(result)

        let clipboard = InMemoryClipboard()
        await clipboard.writeText(result.translatedText)

        let shortcuts = RecordingShortcutRegistry()
        try await shortcuts.register(.quickTranslateDefault, for: .quickTranslate)

        let savedSettings = try await settingsStore.loadSettings()
        let recentHistory = try await historyStore.recent(limit: 1)
        let clipboardText = await clipboard.readText()
        let registeredShortcut = await shortcuts.registeredShortcut(for: .quickTranslate)

        XCTAssertEqual(savedSettings.autoCopyEnabled, true)
        XCTAssertEqual(recentHistory, [result])
        XCTAssertEqual(clipboardText, "sawasdee")
        XCTAssertEqual(registeredShortcut, .quickTranslateDefault)
    }
}
