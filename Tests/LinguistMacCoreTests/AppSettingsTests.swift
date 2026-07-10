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
        XCTAssertEqual(settings.menuBarIcon, .asterisk)
        XCTAssertFalse(settings.doubleCopyTranslationEnabled)
        XCTAssertFalse(settings.dragTranslationEnabled)
        XCTAssertTrue(settings.shortcutsEnabled)
        XCTAssertFalse(settings.screenTranslationSoundEnabled)
        XCTAssertEqual(settings.screenTranslationSoundName, "Glass")
        XCTAssertFalse(settings.screenTranslationNotificationsEnabled)
        XCTAssertEqual(settings.pinnedAppleLanguagePackLanguageIDs, [])
    }

    func testDefaultShortcutsCoverPrimaryInputModes() {
        let settings = AppSettings()

        XCTAssertEqual(settings.screenTranslationShortcut, .screenTranslationDefault)
        XCTAssertEqual(settings.textSelectionShortcut, .textSelectionDefault)
        XCTAssertEqual(settings.quickTranslateShortcut, .quickTranslateDefault)
    }

    func testMenuBarIconDisplayNamesAreHumanReadable() {
        let displayNames: [MenuBarIcon: String] = [
            .asterisk: "Asterisk",
            .lassoBadgeSparkles: "Lasso",
            .timelapse: "Timelapse",
            .aqiMedium: "Air Quality",
            .appSpecular: "App Icon",
            .handRaysFill: "Hand Rays",
            .bonjour: "Bonjour",
            .textQuote: "Text Quote",
            .characterPhonetic: "Phonetic",
            .characterMagnify: "Magnifier",
            .tSquareFill: "T-Square"
        ]

        for icon in MenuBarIcon.allCases {
            XCTAssertEqual(icon.systemImage, icon.rawValue)
            XCTAssertEqual(icon.displayName, displayNames[icon])
            XCTAssertNotEqual(icon.displayName, icon.rawValue)
        }
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

    func testSettingsFallbackWhenSelectedProviderDoesNotSupportLanguagePair() {
        let appleProvider = TranslationProviderDescriptor(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false
        )
        let deeplProvider = TranslationProviderDescriptor(
            id: .deepl,
            displayName: "DeepL",
            requiresAPIKey: true,
            usesNetwork: true,
            configurationStatus: .ready
        )
        let settings = AppSettings(
            targetLanguage: .thai,
            selectedProviderID: .deepl
        )

        let sanitizedSettings = settings.selectingAvailableProvider(from: [appleProvider, deeplProvider])

        XCTAssertEqual(sanitizedSettings.selectedProviderID, .apple)
    }

    func testSettingsRoundTripCodableSchema() throws {
        var settings = AppSettings(sourceLanguage: .japanese, targetLanguage: .korean)
        settings.selectedProviderID = .deepl
        settings.autoCopyEnabled = true
        settings.launchAtLoginEnabled = true
        settings.appLanguage = .korean
        settings.menuBarIcon = .characterMagnify
        settings.doubleCopyTranslationEnabled = true
        settings.shortcutsEnabled = false
        settings.screenTranslationShortcut = KeyboardShortcut(key: "T", modifiers: [.command, .shift])
        settings.screenTranslationSoundEnabled = true
        settings.screenTranslationSoundName = "Ping"
        settings.screenTranslationNotificationsEnabled = true
        settings.popupFontFamily = "Noto Sans Thai"
        settings.popupHeight = 480
        settings.popupOriginX = 120
        settings.popupOriginY = 240
        settings.pinnedAppleLanguagePackLanguageIDs = ["th", "ja"]

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded, settings)
    }

    func testSettingsSanitizeMigrationUnsafeValues() {
        let settings = AppSettings(
            sourceLanguage: .english,
            targetLanguage: .autoDetect,
            popupFontSize: 4,
            popupWidth: 2,
            popupHeight: 8,
            pinnedAppleLanguagePackLanguageIDs: ["th", "auto", "th", "ja"]
        ).sanitized()

        XCTAssertEqual(settings.targetLanguage, .english)
        XCTAssertEqual(settings.popupFontSize, 12)
        XCTAssertEqual(settings.popupWidth, 320)
        XCTAssertEqual(settings.popupHeight, 240)
        XCTAssertEqual(settings.pinnedAppleLanguagePackLanguageIDs, ["th", "ja"])
    }

    func testScreenTranslationSoundPolicyPrefersGlassThenFallsBackToFirstSortedSound() {
        XCTAssertEqual(
            ScreenTranslationSoundPolicy.defaultSoundName(from: ["Ping", "Glass", "Funk"]),
            "Glass"
        )
        XCTAssertEqual(
            ScreenTranslationSoundPolicy.defaultSoundName(from: ["Ping", "Funk"]),
            "Funk"
        )
        XCTAssertEqual(
            ScreenTranslationSoundPolicy.resolvedSoundName("Missing", from: ["Ping", "Funk"]),
            "Funk"
        )
    }

    func testAppLanguageMapsToLocaleAndAppleLanguagesOverride() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertNil(AppLanguage.system.appleLanguages)
        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        XCTAssertEqual(AppLanguage.english.appleLanguages, ["en"])
        XCTAssertEqual(AppLanguage.korean.localeIdentifier, "ko")
        XCTAssertEqual(AppLanguage.korean.locale.identifier, "ko")
        XCTAssertEqual(AppLanguage.korean.appleLanguages, ["ko"])
    }
}
