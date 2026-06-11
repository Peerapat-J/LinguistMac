@testable import LinguistMacCore
import XCTest

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsUsePrivateOnDeviceDefaults() {
        let settings = AppSettings()

        XCTAssertEqual(settings.sourceLanguage, .autoDetect)
        XCTAssertEqual(settings.targetLanguage, .english)
        XCTAssertEqual(settings.selectedProviderID, .apple)
        XCTAssertFalse(settings.autoCopyEnabled)
        XCTAssertFalse(settings.launchAtLoginEnabled)
    }

    func testDefaultShortcutsCoverPrimaryInputModes() {
        let settings = AppSettings()

        XCTAssertEqual(settings.screenTranslationShortcut, .screenTranslationDefault)
        XCTAssertEqual(settings.textSelectionShortcut, .textSelectionDefault)
        XCTAssertEqual(settings.quickTranslateShortcut, .quickTranslateDefault)
    }

    func testSettingsFallbackToAvailableProvider() {
        let appleProvider = TranslationProviderDescriptor(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false
        )
        let settings = AppSettings(selectedProviderID: .deepl)

        let sanitizedSettings = settings.selectingAvailableProvider(from: [appleProvider])

        XCTAssertEqual(sanitizedSettings.selectedProviderID, .apple)
    }
}
