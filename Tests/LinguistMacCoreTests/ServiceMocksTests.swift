import Foundation
@testable import LinguistMacCore
import XCTest

private func XCTAssertThrowsError(
    _ expression: () async throws -> Void,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        try await expression()
        let failureMessage = message()
        XCTFail(
            failureMessage.isEmpty ? "XCTAssertThrowsError failed: did not throw error" : failureMessage,
            file: file,
            line: line
        )
    } catch {
        errorHandler(error)
    }
}

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
            languageAvailability: StubLanguageAvailabilityChecker(readiness: .ready),
            settingsStore: InMemoryAppSettingsStore(),
            apiKeyStore: InMemoryAPIKeyStore(),
            launchAtLogin: StubLaunchAtLoginService(),
            historyStore: InMemoryTranslationHistoryStore(),
            permissionChecker: StubPermissionChecker(statuses: [.screenRecording: .granted]),
            clipboard: InMemoryClipboard(),
            selectedTextCapture: StubSelectedTextCapture(result: .success("hello")),
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

    func testServicesSurfaceMockTranslationFailure() async throws {
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .screenSelection,
            providerID: .apple
        )
        let region = CapturedScreenRegion(imageData: Data([1, 2, 3]))
        let expectedFailure = TranslationFailure.providerFailed("translator unavailable")
        let provider = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "unused",
            failure: expectedFailure
        )
        let services = LinguistServices(
            screenCapture: StubScreenCaptureService(result: .success(region)),
            ocr: StubOCRService(result: .success(RecognizedText(text: request.text, language: .english))),
            translatorRegistry: StubTranslationProviderRegistry(provider: provider),
            languageAvailability: StubLanguageAvailabilityChecker(readiness: .ready),
            settingsStore: InMemoryAppSettingsStore(),
            apiKeyStore: InMemoryAPIKeyStore(),
            launchAtLogin: StubLaunchAtLoginService(),
            historyStore: InMemoryTranslationHistoryStore(),
            permissionChecker: StubPermissionChecker(statuses: [.screenRecording: .granted]),
            clipboard: InMemoryClipboard(),
            selectedTextCapture: StubSelectedTextCapture(result: .success("hello")),
            shortcutRegistry: RecordingShortcutRegistry()
        )

        let capturedRegion = try await services.screenCapture.captureSelection()
        let recognizedText = try await services.ocr.recognizeText(in: capturedRegion)
        let translator = try await services.translatorRegistry.provider(for: request.providerID)

        XCTAssertEqual(capturedRegion, region)
        XCTAssertEqual(recognizedText.text, "hello")
        await XCTAssertThrowsError {
            _ = try await translator.translate(request)
        } errorHandler: { error in
            XCTAssertEqual(error as? TranslationFailure, expectedFailure)
        }
    }

    func testRegistryFallsBackFromUnsupportedPreferredProvider() async {
        let apple = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "sawasdee"
        )
        let deepl = StubTranslationProvider(
            id: .deepl,
            displayName: "DeepL",
            requiresAPIKey: true,
            usesNetwork: true,
            translatedText: "unused"
        )
        let registry = DefaultTranslationProviderRegistry(providers: [deepl, apple])

        let providerID = await registry.supportedProviderID(
            preferred: .deepl,
            sourceLanguage: .english,
            targetLanguage: .thai
        )

        XCTAssertEqual(providerID, .apple)
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

        let apiKeyStore = InMemoryAPIKeyStore()
        try await apiKeyStore.saveAPIKey("test-key", for: .microsoftAzure)
        try await apiKeyStore.saveAPIRegion("eastus", for: .microsoftAzure)

        let savedSettings = try await settingsStore.loadSettings()
        let recentHistory = try await historyStore.recent(limit: 1)
        let clipboardText = await clipboard.readText()
        let registeredShortcut = await shortcuts.registeredShortcut(for: .quickTranslate)
        let savedAPIKey = try await apiKeyStore.apiKey(for: .microsoftAzure)
        let savedAPIRegion = try await apiKeyStore.apiRegion(for: .microsoftAzure)

        XCTAssertEqual(savedSettings.autoCopyEnabled, true)
        XCTAssertEqual(recentHistory, [result])
        XCTAssertEqual(clipboardText, "sawasdee")
        XCTAssertEqual(registeredShortcut, .quickTranslateDefault)
        XCTAssertEqual(savedAPIKey, "test-key")
        XCTAssertEqual(savedAPIRegion, "eastus")
    }
}
