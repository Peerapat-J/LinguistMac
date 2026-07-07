import Foundation
@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelLanguagePackTests: XCTestCase {
    func testTranslationSettingsSearchMatchesLanguagePackTerms() {
        let languagePackQueries = [
            "Apple Language Packs",
            "Language Groups",
            "Search language packs",
            "Thai",
            "Japanese",
            "Download Failed",
            "Needs Download",
            "Still Downloading",
            "Keep Checking",
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
            model.appleLanguagePackSupportedLanguages.contains(where: \.supportsAutoDetect)
        )
    }

    func testPrepareSelectedAppleLanguagePackUpdatesSelectionAndSetupReadiness() async {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareSelectedAppleLanguagePack()

        let requestsByPairID = Dictionary(
            uniqueKeysWithValues: model.appleLanguagePackPreparationRequests.map { ($0.pair.id, $0) }
        )

        XCTAssertEqual(Set(model.appleLanguagePackPreparationRequests.map(\.pair)), Set(pair.bidirectionalPairs))
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)

        await languageAvailability.setReadiness(.ready, for: pair)
        await languageAvailability.setReadiness(.ready, for: pair.reversed)
        await model.finishAppleLanguagePackPreparation(
            for: pair,
            requestID: requestsByPairID[pair.id]?.id,
            result: .success(())
        )
        await model.finishAppleLanguagePackPreparation(
            for: pair.reversed,
            requestID: requestsByPairID[pair.reversed.id]?.id,
            result: .success(())
        )

        let readinessItems = Dictionary(uniqueKeysWithValues: model.readiness.items.map { ($0.kind, $0) })

        XCTAssertTrue(model.appleLanguagePackPreparationRequests.isEmpty)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .ready)
        XCTAssertEqual(model.appleLanguagePackSelection.message, "Language pack is ready.")
        XCTAssertEqual(readinessItems[.appleTranslation]?.statusText, "Ready")
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

        await model.refreshAppleLanguagePackGroup(for: .thai)

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
        let supportedLanguageCount = model.appleLanguagePackSupportedLanguages.count
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

    func testPrepareAppleLanguagePackUpdatesGroupedRowsSelectionAndSetupReadiness() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroup(for: .english)
        await model.prepareAppleLanguagePack(for: pair)

        let requestsByPairID = Dictionary(
            uniqueKeysWithValues: model.appleLanguagePackPreparationRequests.map { ($0.pair.id, $0) }
        )

        XCTAssertEqual(Set(model.appleLanguagePackPreparationRequests.map(\.pair)), Set(pair.bidirectionalPairs))
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)

        await languageAvailability.setReadiness(.ready, for: pair)
        await languageAvailability.setReadiness(.ready, for: pair.reversed)
        await model.finishAppleLanguagePackPreparation(
            for: pair,
            requestID: requestsByPairID[pair.id]?.id,
            result: .success(())
        )
        await model.finishAppleLanguagePackPreparation(
            for: pair.reversed,
            requestID: requestsByPairID[pair.reversed.id]?.id,
            result: .success(())
        )

        let readinessItems = Dictionary(uniqueKeysWithValues: model.readiness.items.map { ($0.kind, $0) })
        let englishRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .english,
            pairID: pair.id
        )
        let thaiRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .thai,
            pairID: pair.id
        )

        XCTAssertTrue(model.appleLanguagePackPreparationRequests.isEmpty)
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .ready)
        XCTAssertEqual(model.appleLanguagePackSelection.message, "Language pack is ready.")
        XCTAssertEqual(englishRow.readiness, .ready)
        XCTAssertEqual(englishRow.message, "Language pack is ready.")
        XCTAssertEqual(thaiRow.readiness, .ready)
        XCTAssertEqual(thaiRow.message, "Language pack is ready.")
        XCTAssertEqual(readinessItems[.appleTranslation]?.statusText, "Ready")
    }

    func testSuccessfulAppleLanguagePackPreparationRefreshesAllGroupReadiness() async throws {
        let preparedPair = AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .japanese)
        let relatedPair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .japanese)
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: [
                preparedPair.id: .needsDownload,
                preparedPair.reversed.id: .needsDownload,
                relatedPair.id: .needsDownload,
                relatedPair.reversed.id: .needsDownload
            ]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .japanese),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroup(for: .thai)
        let initialRelatedRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .english,
            pairID: relatedPair.id
        )

        await model.prepareAppleLanguagePack(for: preparedPair)
        let request = try XCTUnwrap(
            model.appleLanguagePackPreparationRequests.first { $0.pair == preparedPair }
        )
        await languageAvailability.setReadiness(.ready, for: preparedPair)
        await languageAvailability.setReadiness(.ready, for: preparedPair.reversed)
        await languageAvailability.setReadiness(.ready, for: relatedPair)
        await languageAvailability.setReadiness(.ready, for: relatedPair.reversed)
        await model.finishAppleLanguagePackPreparation(
            for: preparedPair,
            requestID: request.id,
            result: .success(())
        )

        let refreshedRelatedRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .english,
            pairID: relatedPair.id
        )

        XCTAssertEqual(initialRelatedRow.readiness, .unknown)
        XCTAssertEqual(refreshedRelatedRow.readiness, .ready)
    }
}

@MainActor
final class AppShellModelLanguagePackDownloadTests: XCTestCase {
    func testPrepareAppleLanguagePackAllowsMultipleActiveRequests() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: [
                "en->th": .needsDownload,
                "ja->th": .needsDownload
            ]
        )
        let currentPair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let secondPair = AppleLanguagePackPair(sourceLanguage: .japanese, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.prepareAppleLanguagePack(for: currentPair)
        await model.prepareAppleLanguagePack(for: secondPair)

        let activePairs = Set(model.appleLanguagePackPreparationRequests.map(\.pair))
        let currentRequest = try XCTUnwrap(
            model.appleLanguagePackPreparationRequests.first { $0.pair == currentPair }
        )
        let secondRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .japanese,
            pairID: secondPair.id
        )

        XCTAssertEqual(activePairs, Set(currentPair.bidirectionalPairs + secondPair.bidirectionalPairs))
        XCTAssertEqual(model.appleLanguagePackSelection.pair, currentPair)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)
        XCTAssertTrue(secondRow.isPreparing)

        await languageAvailability.setReadiness(.ready, for: currentPair)
        await model.finishAppleLanguagePackPreparation(
            for: currentPair,
            requestID: currentRequest.id,
            result: .success(())
        )

        let remainingPairs = Set(model.appleLanguagePackPreparationRequests.map(\.pair))
        let updatedSecondRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .japanese,
            pairID: secondPair.id
        )

        XCTAssertEqual(remainingPairs, Set([currentPair.reversed] + secondPair.bidirectionalPairs))
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .ready)
        XCTAssertFalse(model.appleLanguagePackSelection.isPreparing)
        XCTAssertTrue(updatedSecondRow.isPreparing)
    }

    func testMissingLanguagePackFailureKeepsPreparationActiveWhileMacOSDownloads() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareAppleLanguagePack(for: pair)
        let request = try XCTUnwrap(model.appleLanguagePackPreparationRequests.first { $0.pair == pair })
        await model.finishAppleLanguagePackPreparation(
            for: pair,
            requestID: request.id,
            result: .failure(.missingLanguagePack(.apple))
        )

        XCTAssertTrue(model.appleLanguagePackPreparationRequests.contains { $0.pair == pair })
        XCTAssertTrue(model.appleLanguagePackPreparationRequests.contains { $0.pair == pair.reversed })
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)
        XCTAssertEqual(
            model.appleLanguagePackSelection.message,
            "macOS is still downloading this language pack. LinguistMac will keep checking."
        )
    }

    func testLanguagePackRecheckMarksBackgroundDownloadReady() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareAppleLanguagePack(for: pair)
        let request = try XCTUnwrap(model.appleLanguagePackPreparationRequests.first { $0.pair == pair })
        await model.finishAppleLanguagePackPreparation(
            for: pair,
            requestID: request.id,
            result: .failure(.missingLanguagePack(.apple))
        )
        await languageAvailability.setReadiness(.ready, for: pair)
        await model.recheckAppleLanguagePackPreparation(requestID: request.id)

        XCTAssertFalse(model.appleLanguagePackPreparationRequests.contains { $0.pair == pair })
        XCTAssertTrue(model.appleLanguagePackPreparationRequests.contains { $0.pair == pair.reversed })
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .ready)
        XCTAssertFalse(model.appleLanguagePackSelection.isPreparing)
        XCTAssertEqual(model.appleLanguagePackSelection.message, "Language pack is ready.")
    }

    func testStaleAppleLanguagePackPreparationTimesOutAndRechecksReadiness() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareAppleLanguagePack(for: pair)

        let request = try XCTUnwrap(model.appleLanguagePackPreparationRequests.first)
        let staleNow = request.startedAt.addingTimeInterval(AppShellModel.appleLanguagePackPreparationTimeout + 1)
        await model.clearStaleAppleLanguagePackPreparationIfNeeded(now: staleNow)

        XCTAssertTrue(model.appleLanguagePackPreparationRequests.isEmpty)
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertFalse(model.appleLanguagePackSelection.isPreparing)
        XCTAssertEqual(model.appleLanguagePackSelection.message, "Download did not finish. Try Download again.")
    }

    func testCancelAppleLanguagePackPreparationClearsRequestAndRows() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroup(for: .english)
        await model.prepareAppleLanguagePack(for: pair)
        await model.cancelAppleLanguagePackPreparation(for: pair)

        let preparedPairIDs = await languageAvailability.preparedPairIDs()
        let englishRow = try languagePackRow(
            in: model.appleLanguagePackGroups,
            language: .english,
            pairID: pair.id
        )

        XCTAssertTrue(preparedPairIDs.isEmpty)
        XCTAssertTrue(model.appleLanguagePackPreparationRequests.isEmpty)
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertFalse(model.appleLanguagePackSelection.isPreparing)
        XCTAssertEqual(model.appleLanguagePackSelection.message, "Download canceled. Try Download again.")
        XCTAssertEqual(englishRow.readiness, .needsDownload)
        XCTAssertFalse(englishRow.isPreparing)
        XCTAssertEqual(englishRow.message, "Download canceled. Try Download again.")
    }

    func testPrepareSelectedAppleLanguagePackSkipsAutoDetectSource() async {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload],
            preparedReadiness: .ready
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareSelectedAppleLanguagePack()

        let preparedPairIDs = await languageAvailability.preparedPairIDs()
        XCTAssertNil(model.appleLanguagePackSelection.pair)
        XCTAssertFalse(model.appleLanguagePackSelection.canPrepare)
        XCTAssertTrue(preparedPairIDs.isEmpty)
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
    private let preparedReadiness: LanguagePackReadiness
    private var preparedPairs: [String]
    private var readinessPairs: [String]

    init(
        defaultReadiness: LanguagePackReadiness = .ready,
        readinessByPair: [String: LanguagePackReadiness] = [:],
        preparedReadiness: LanguagePackReadiness = .ready
    ) {
        self.defaultReadiness = defaultReadiness
        self.readinessByPair = readinessByPair
        self.preparedReadiness = preparedReadiness
        preparedPairs = []
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
        preparedPairs.append(pairID)
        readinessByPair[pairID] = preparedReadiness
        return preparedReadiness
    }

    func preparedPairIDs() -> [String] {
        preparedPairs
    }

    func readinessPairIDs() -> [String] {
        readinessPairs
    }

    func setReadiness(_ readiness: LanguagePackReadiness, for pair: AppleLanguagePackPair) {
        readinessByPair[pair.id] = readiness
    }

    private static func pairID(
        source: TranslationLanguage,
        target: TranslationLanguage
    ) -> String {
        "\(source.id)->\(target.id)"
    }
}
