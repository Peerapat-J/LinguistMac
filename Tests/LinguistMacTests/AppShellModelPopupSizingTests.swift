@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelPopupSizingTests: XCTestCase {
    func testRememberPopupWindowFramePreservesConfiguredSize() {
        let model = AppShellModel(services: makeServices())
        model.settings.popupWidth = 640
        model.settings.popupHeight = 480

        model.rememberPopupWindowFrame(CGRect(x: 12, y: 24, width: 900, height: 120))

        XCTAssertEqual(model.settings.popupOriginX, 12)
        XCTAssertEqual(model.settings.popupOriginY, 24)
        XCTAssertEqual(model.settings.popupWidth, 640)
        XCTAssertEqual(model.settings.popupHeight, 480)
        XCTAssertEqual(
            model.savedPopupWindowFrame,
            CGRect(x: 12, y: 24, width: 640, height: 480)
        )
    }

    func testNotePopupManualResizeDisablesFutureAutomaticSizing() {
        let model = AppShellModel(services: makeServices())

        model.notePopupManualResize()

        XCTAssertTrue(model.hasManuallyResizedPopup)
    }

    func testNewTranslationResetsManualPopupResize() {
        let model = AppShellModel(services: makeServices())
        model.notePopupManualResize()
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )

        model.popupState = .loading(request)

        XCTAssertFalse(model.hasManuallyResizedPopup)
    }

    func testFailureResetsManualPopupResize() {
        let model = AppShellModel(services: makeServices())
        model.notePopupManualResize()

        model.popupState = .failed(.captureCancelled, originalText: nil)

        XCTAssertFalse(model.hasManuallyResizedPopup)
    }

    func testSameResultLayoutChangesPreserveManualPopupResize() {
        let model = AppShellModel(services: makeServices())
        let result = makeResult(text: "hello")
        model.popupState = .success(result, showsOriginal: false)
        model.notePopupManualResize()

        model.popupState = .success(result, showsOriginal: true)

        XCTAssertTrue(model.hasManuallyResizedPopup)
    }

    private func makeServices() -> LinguistServices {
        LinguistServices(
            screenCapture: TestScreenCaptureService(),
            ocr: TestOCRService(),
            translatorRegistry: TestTranslationProviderRegistry(),
            languageAvailability: TestLanguageAvailabilityChecker(),
            settingsStore: TestAppSettingsStore(),
            apiKeyStore: TestAPIKeyStore(),
            launchAtLogin: TestLaunchAtLoginService(),
            historyStore: TestTranslationHistoryStore(),
            permissionChecker: TestPermissionChecker(),
            clipboard: TestClipboard(),
            selectedTextCapture: TestSelectedTextCapture(),
            shortcutRegistry: TestShortcutRegistry(),
            screenTranslationSoundPlayer: NoOpScreenTranslationSoundPlayer(),
            screenTranslationNotifier: NoOpScreenTranslationNotifier()
        )
    }

    private func makeResult(text: String) -> TranslationResult {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )
        return TranslationResult(request: request, translatedText: text)
    }
}
