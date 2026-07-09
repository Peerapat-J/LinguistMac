import Foundation
@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelLanguagePackTests: XCTestCase {
    func testTranslationSettingsSearchMatchesLanguagePackTerms() {
        let languagePackQueries = [
            "Apple Language Packs",
            "Languages",
            "Search language packs",
            "Thai",
            "Japanese",
            "Download Failed",
            "Needs Download",
            "Downloading",
            "Select Source",
            "Not Required",
            "Pin",
            "Current"
        ]

        for query in languagePackQueries {
            XCTAssertTrue(
                SettingsSectionID.translation.matchesSearch(query),
                "Expected Translation settings to match sidebar search query: \(query)"
            )
        }
    }

    func testRefreshAppleLanguagePackSelectionMapsCurrentPairReadiness() async {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["th->en": .needsDownload]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()

        let selection = model.appleLanguagePackSelection
        XCTAssertEqual(selection.pair, AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .english))
        XCTAssertEqual(selection.readiness, .needsDownload)
        XCTAssertTrue(selection.canPrepare)
        XCTAssertFalse(
            AppleLanguagePackCatalog.supportedLanguages(from: TranslationLanguageCatalog.defaultLanguages)
                .contains(where: \.supportsAutoDetect)
        )
    }

    func testRefreshAppleLanguagePackGroupMapsReadinessForLanguageRows() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: [
                "th->en": .needsDownload,
                "en->th": .ready,
                "th->ja": .unavailable
            ]
        )
        let currentPair = AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .english)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroups()

        let thaiGroup = try XCTUnwrap(model.appleLanguagePackGroups.first { $0.language == .thai })
        let thaiEnglishRow = try XCTUnwrap(thaiGroup.rows.first { $0.pairs.contains(currentPair) })
        let thaiJapaneseRow = try XCTUnwrap(
            thaiGroup.rows.first {
                $0.pairs.contains(AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .japanese))
            }
        )

        XCTAssertEqual(model.appleLanguagePackSelection.pair, currentPair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertEqual(thaiEnglishRow.readiness, .needsDownload)
        XCTAssertEqual(thaiEnglishRow.readinessByPairID["th->en"], .needsDownload)
        XCTAssertEqual(thaiEnglishRow.readinessByPairID["en->th"], .ready)
        XCTAssertTrue(thaiEnglishRow.isCurrentPair)
        XCTAssertEqual(thaiJapaneseRow.readiness, .unavailable)
        XCTAssertFalse(
            thaiGroup.rows.contains {
                $0.pairs.contains { $0.sourceLanguage == $0.targetLanguage }
            }
        )
        XCTAssertTrue(
            thaiGroup.rows.allSatisfy {
                $0.pairs.allSatisfy { $0.sourceLanguage == .thai || $0.targetLanguage == .thai }
            }
        )
    }

    func testRefreshAppleLanguagePackGroupsChecksAllUniquePairs() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: [
                "th->en": .needsDownload,
                "en->th": .ready,
                "th->ja": .unavailable
            ]
        )
        let currentPair = AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .english)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )
        let supportedLanguageCount = AppleLanguagePackCatalog
            .supportedLanguages(from: TranslationLanguageCatalog.defaultLanguages)
            .count
        let expectedUniquePairCount = supportedLanguageCount * (supportedLanguageCount - 1)

        await model.refreshAppleLanguagePackGroups()

        let readinessPairIDs = await languageAvailability.readinessPairIDs()
        let thaiGroup = try XCTUnwrap(model.appleLanguagePackGroups.first { $0.language == .thai })
        let thaiEnglishRow = try XCTUnwrap(thaiGroup.rows.first { $0.pairs.contains(currentPair) })
        let thaiJapaneseRow = try XCTUnwrap(
            thaiGroup.rows.first {
                $0.pairs.contains(AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .japanese))
            }
        )

        XCTAssertEqual(Set(readinessPairIDs).count, expectedUniquePairCount)
        XCTAssertEqual(readinessPairIDs.count, expectedUniquePairCount)
        XCTAssertFalse(model.appleLanguagePackGroups.flatMap(\.rows).contains { $0.readiness == .unknown })
        XCTAssertEqual(model.appleLanguagePackSelection.pair, currentPair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertEqual(thaiEnglishRow.readiness, .needsDownload)
        XCTAssertEqual(thaiEnglishRow.readinessByPairID["th->en"], .needsDownload)
        XCTAssertEqual(thaiEnglishRow.readinessByPairID["en->th"], .ready)
        XCTAssertEqual(thaiJapaneseRow.readiness, .unavailable)
    }

    func testTogglePinnedAppleLanguagePackGroupMovesGroupFirstAndUpdatesSettings() {
        let model = AppShellModel(
            services: makeLanguagePackTestServices(
                languageAvailability: LanguagePackTestAvailabilityChecker()
            )
        )

        model.togglePinnedAppleLanguagePackGroup(.thai)

        XCTAssertEqual(model.settings.pinnedAppleLanguagePackLanguageIDs, ["th"])
        XCTAssertEqual(model.appleLanguagePackGroups.first?.language, .thai)
        XCTAssertEqual(model.appleLanguagePackGroups.first?.isPinned, true)

        model.togglePinnedAppleLanguagePackGroup(.thai)

        XCTAssertEqual(model.settings.pinnedAppleLanguagePackLanguageIDs, [])
        XCTAssertNotEqual(model.appleLanguagePackGroups.first?.language, .thai)
        XCTAssertFalse(model.appleLanguagePackGroups.contains { $0.isPinned })
    }

    func testRefreshAppleLanguagePackSelectionSkipsAutoDetectSource() async {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()

        XCTAssertNil(model.appleLanguagePackSelection.pair)
        XCTAssertFalse(model.appleLanguagePackSelection.canPrepare)
    }
}

final class UserDefaultsLanguagePackSettingsTests: XCTestCase {
    func testPinnedLanguagePackGroupsRoundTripThroughUserDefaults() async throws {
        let suiteName = "LinguistMacTests.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        let store = try UserDefaultsAppSettingsStore(
            defaults: XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        let settings = AppSettings(pinnedAppleLanguagePackLanguageIDs: ["th", "ja"])

        try await store.saveSettings(settings)
        let loadedSettings = try await store.loadSettings()

        XCTAssertEqual(loadedSettings.pinnedAppleLanguagePackLanguageIDs, ["th", "ja"])
    }
}

private func makeLanguagePackTestServices(
    languageAvailability: any LanguageAvailabilityChecking
) -> LinguistServices {
    let noOpService = SetupPermissionNoOpService()
    return LinguistServices(
        screenCapture: noOpService,
        ocr: noOpService,
        translatorRegistry: noOpService,
        languageAvailability: languageAvailability,
        settingsStore: noOpService,
        apiKeyStore: noOpService,
        launchAtLogin: noOpService,
        historyStore: noOpService,
        permissionChecker: noOpService,
        clipboard: noOpService,
        selectedTextCapture: noOpService,
        shortcutRegistry: noOpService,
        screenTranslationSoundPlayer: NoOpScreenTranslationSoundPlayer(),
        screenTranslationNotifier: NoOpScreenTranslationNotifier()
    )
}

private func languagePackRow(
    in groups: [AppleLanguagePackGroup],
    language: TranslationLanguage,
    pairID: String
) throws -> AppleLanguagePackReadinessRow {
    let group = try XCTUnwrap(groups.first { $0.language == language })
    return try XCTUnwrap(group.rows.first { row in
        row.pairs.contains { $0.id == pairID }
    })
}

private actor LanguagePackTestAvailabilityChecker: LanguageAvailabilityChecking {
    private var readinessByPair: [String: LanguagePackReadiness]
    private let defaultReadiness: LanguagePackReadiness
    private var readinessPairs: [String]

    init(
        defaultReadiness: LanguagePackReadiness = .ready,
        readinessByPair: [String: LanguagePackReadiness] = [:]
    ) {
        self.defaultReadiness = defaultReadiness
        self.readinessByPair = readinessByPair
        readinessPairs = []
    }

    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        _ = sampleText
        let pairID = Self.pairID(source: source, target: target)
        readinessPairs.append(pairID)
        return readinessByPair[pairID] ?? defaultReadiness
    }

    func prepareLanguagePack(
        from source: TranslationLanguage,
        to target: TranslationLanguage
    ) async throws -> LanguagePackReadiness {
        let pairID = Self.pairID(source: source, target: target)
        return readinessByPair[pairID] ?? defaultReadiness
    }

    func readinessPairIDs() -> [String] {
        readinessPairs
    }

    private static func pairID(
        source: TranslationLanguage,
        target: TranslationLanguage
    ) -> String {
        "\(source.id)->\(target.id)"
    }
}
