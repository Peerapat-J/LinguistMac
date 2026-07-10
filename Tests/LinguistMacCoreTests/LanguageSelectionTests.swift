@testable import LinguistMacCore
import XCTest

final class LanguageSelectionTests: XCTestCase {
    func testCatalogExcludesAutoDetectFromTargets() {
        XCTAssertTrue(TranslationLanguageCatalog.defaultLanguages.contains(.autoDetect))
        XCTAssertFalse(TranslationLanguageCatalog.targetLanguages.contains(.autoDetect))
        XCTAssertEqual(TranslationLanguageCatalog.language(forID: "th"), .thai)
    }

    func testCatalogIncludesAppleTranslationLanguages() {
        XCTAssertEqual(
            TranslationLanguageCatalog.defaultLanguages.map(\.id),
            [
                "auto",
                "ar",
                "nl",
                "en",
                "fr",
                "de",
                "hi",
                "id",
                "it",
                "ja",
                "ko",
                "zh-Hans",
                "zh-Hant",
                "pl",
                "pt-BR",
                "ru",
                "es",
                "th",
                "tr",
                "uk",
                "vi"
            ]
        )
    }

    func testCatalogMapsLocaleVariantsToSupportedLanguages() {
        XCTAssertEqual(TranslationLanguageCatalog.language(forID: "en-US"), .english)
        XCTAssertEqual(TranslationLanguageCatalog.language(forID: "pt"), .brazilianPortuguese)
        XCTAssertEqual(TranslationLanguageCatalog.language(forID: "zh-CN"), .simplifiedChinese)
        XCTAssertEqual(TranslationLanguageCatalog.language(forID: "zh-TW"), .traditionalChinese)
    }

    func testLanguageSelectionSwapsConcreteLanguages() {
        var selection = LanguageSelection(source: .english, target: .thai)

        XCTAssertTrue(selection.canSwap)
        selection.swap()

        XCTAssertEqual(selection.source, .thai)
        XCTAssertEqual(selection.target, .english)
    }

    func testLanguageSelectionDoesNotSwapAutoDetectSource() {
        var selection = LanguageSelection(source: .autoDetect, target: .thai)

        XCTAssertFalse(selection.canSwap)
        selection.swap()

        XCTAssertEqual(selection.source, .autoDetect)
        XCTAssertEqual(selection.target, .thai)
    }

    func testSettingsExposeLanguageSelection() {
        var settings = AppSettings(sourceLanguage: .english, targetLanguage: .thai)

        settings.languageSelection.swap()

        XCTAssertEqual(settings.sourceLanguage, .thai)
        XCTAssertEqual(settings.targetLanguage, .english)
    }
}
