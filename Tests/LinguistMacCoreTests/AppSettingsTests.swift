import Foundation
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
        XCTAssertEqual(settings.appLanguage, .system)
        XCTAssertFalse(settings.doubleCopyTranslationEnabled)
        XCTAssertFalse(settings.dragTranslationEnabled)
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

    func testSettingsRoundTripCodableSchema() throws {
        var settings = AppSettings(sourceLanguage: .japanese, targetLanguage: .korean)
        settings.selectedProviderID = .deepl
        settings.autoCopyEnabled = true
        settings.launchAtLoginEnabled = true
        settings.appLanguage = .korean
        settings.doubleCopyTranslationEnabled = true
        settings.screenTranslationShortcut = KeyboardShortcut(key: "T", modifiers: [.command, .shift])

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded, settings)
    }

    func testSettingsSanitizeMigrationUnsafeValues() {
        let settings = AppSettings(
            sourceLanguage: .english,
            targetLanguage: .autoDetect,
            popupFontSize: 4,
            popupWidth: 2
        ).sanitized()

        XCTAssertEqual(settings.targetLanguage, .english)
        XCTAssertEqual(settings.popupFontSize, 12)
        XCTAssertEqual(settings.popupWidth, 320)
    }
}
