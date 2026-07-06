@testable import LinguistMacCore
import XCTest

final class AppleLanguagePackModelsTests: XCTestCase {
    func testAppleLanguagePackCatalogBuildsGroupsForEachSupportedLanguage() {
        let groups = AppleLanguagePackCatalog.groups(
            from: TranslationLanguageCatalog.defaultLanguages,
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english)
        )
        let supportedLanguages = TranslationLanguageCatalog.defaultLanguages.filter { !$0.supportsAutoDetect }
        let thaiGroup = groups.first { $0.language == .thai }
        let expectedRowCount = (supportedLanguages.count - 1) * 2

        XCTAssertEqual(groups.map(\.language), supportedLanguages)
        XCTAssertEqual(thaiGroup?.rows.count, expectedRowCount)
        XCTAssertEqual(
            thaiGroup?.rows.first?.pair,
            AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .english)
        )
        XCTAssertFalse(thaiGroup?.rows.contains { $0.pair.sourceLanguage == $0.pair.targetLanguage } ?? true)
        XCTAssertTrue(
            thaiGroup?.rows.contains(
                AppleLanguagePackReadinessRow(
                    pair: AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai),
                    readiness: .unknown,
                    isCurrentPair: false
                )
            ) ?? false
        )
    }

    func testAppleLanguagePackReadinessRowOnlyPreparesNeedsDownloadPair() {
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let needsDownload = AppleLanguagePackReadinessRow(
            pair: pair,
            readiness: .needsDownload,
            isCurrentPair: false
        )
        let preparing = AppleLanguagePackReadinessRow(
            pair: pair,
            readiness: .needsDownload,
            isCurrentPair: false,
            isPreparing: true
        )
        let ready = AppleLanguagePackReadinessRow(
            pair: pair,
            readiness: .ready,
            isCurrentPair: false
        )

        XCTAssertTrue(needsDownload.canPrepare)
        XCTAssertFalse(preparing.canPrepare)
        XCTAssertFalse(ready.canPrepare)
    }
}
