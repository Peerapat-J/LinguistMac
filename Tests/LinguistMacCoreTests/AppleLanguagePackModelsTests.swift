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
        let expectedRowCount = supportedLanguages.count - 1
        let thaiEnglishPairs = [
            AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .english),
            AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        ]

        XCTAssertEqual(groups.map(\.language), supportedLanguages)
        XCTAssertEqual(thaiGroup?.rows.count, expectedRowCount)
        XCTAssertEqual(
            thaiGroup?.rows.first?.pairs,
            thaiEnglishPairs
        )
        XCTAssertEqual(thaiGroup?.rows.first?.displayName, "Thai ↔ English")
        XCTAssertFalse(
            thaiGroup?.rows.contains {
                $0.pairs.contains { $0.sourceLanguage == $0.targetLanguage }
            } ?? true
        )
        XCTAssertTrue(
            thaiGroup?.rows.contains { $0.pairs == thaiEnglishPairs } ?? false
        )
    }

    func testAppleLanguagePackCatalogOrdersPinnedGroupsFirst() {
        let groups = AppleLanguagePackCatalog.groups(
            from: TranslationLanguageCatalog.defaultLanguages,
            settings: AppSettings(pinnedAppleLanguagePackLanguageIDs: ["th", "ja"])
        )

        XCTAssertEqual(groups.prefix(2).map(\.language), [.thai, .japanese])
        XCTAssertEqual(groups.prefix(2).map(\.isPinned), [true, true])
        XCTAssertFalse(groups.dropFirst(2).contains { $0.isPinned })
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
        XCTAssertFalse(needsDownload.hasPreparationFailure)
        XCTAssertTrue(
            AppleLanguagePackReadinessRow(
                pair: pair,
                readiness: .needsDownload,
                isCurrentPair: false,
                message: "Apple Translation could not prepare this language pair.",
                messageKind: .failure
            ).hasPreparationFailure
        )
        XCTAssertTrue(
            AppleLanguagePackReadinessRow(
                pair: pair,
                readiness: .needsDownload,
                isCurrentPair: false,
                message: "Download not completed yet. Try again later.",
                messageKind: .notCompleted
            ).hasIncompletePreparation
        )
        XCTAssertFalse(
            AppleLanguagePackReadinessRow(
                pair: pair,
                readiness: .needsDownload,
                isCurrentPair: false,
                message: "Download not completed yet. Try again later.",
                messageKind: .notCompleted
            ).hasPreparationFailure
        )
    }
}
