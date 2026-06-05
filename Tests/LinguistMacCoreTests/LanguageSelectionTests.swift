@testable import LinguistMacCore
import XCTest

final class LanguageSelectionTests: XCTestCase {
    func testCatalogExcludesAutoDetectFromTargets() {
        XCTAssertTrue(TranslationLanguageCatalog.defaultLanguages.contains(.autoDetect))
        XCTAssertFalse(TranslationLanguageCatalog.targetLanguages.contains(.autoDetect))
        XCTAssertEqual(TranslationLanguageCatalog.language(forID: "th"), .thai)
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
