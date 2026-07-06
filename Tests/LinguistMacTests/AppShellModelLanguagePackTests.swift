@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelLanguagePackTests: XCTestCase {
    func testRefreshAppleLanguagePackSelectionMapsCurrentPairReadiness() async {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["th->en": .needsDownload]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english),
            services: makeServices(languageAvailability: languageAvailability)
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
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareSelectedAppleLanguagePack()

        let preparedPairIDs = await languageAvailability.preparedPairIDs()

        XCTAssertTrue(preparedPairIDs.isEmpty)
        XCTAssertEqual(model.appleLanguagePackPreparationRequests.map(\.pair), [pair])
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)

        await languageAvailability.setReadiness(.ready, for: pair)
        await model.finishAppleLanguagePackPreparation(for: pair, result: .success(()))

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
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroup(for: .thai)

        let thaiGroup = try XCTUnwrap(model.appleLanguagePackGroups.first { $0.language == .thai })
        let rowsByPair = Dictionary(uniqueKeysWithValues: thaiGroup.rows.map { ($0.id, $0) })

        XCTAssertEqual(model.appleLanguagePackSelection.pair, currentPair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertEqual(rowsByPair["th->en"]?.readiness, .needsDownload)
        XCTAssertEqual(rowsByPair["th->en"]?.isCurrentPair, true)
        XCTAssertEqual(rowsByPair["en->th"]?.readiness, .ready)
        XCTAssertEqual(rowsByPair["th->ja"]?.readiness, .unavailable)
        XCTAssertFalse(thaiGroup.rows.contains { $0.pair.sourceLanguage == $0.pair.targetLanguage })
        XCTAssertTrue(
            thaiGroup.rows.allSatisfy {
                $0.pair.sourceLanguage == .thai || $0.pair.targetLanguage == .thai
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
            services: makeServices(languageAvailability: languageAvailability)
        )
        let supportedLanguageCount = model.appleLanguagePackSupportedLanguages.count
        let expectedUniquePairCount = supportedLanguageCount * (supportedLanguageCount - 1)

        await model.refreshAppleLanguagePackGroups()

        let readinessPairIDs = await languageAvailability.readinessPairIDs()
        let thaiGroup = try XCTUnwrap(model.appleLanguagePackGroups.first { $0.language == .thai })
        let rowsByPair = Dictionary(uniqueKeysWithValues: thaiGroup.rows.map { ($0.id, $0) })

        XCTAssertEqual(Set(readinessPairIDs).count, expectedUniquePairCount)
        XCTAssertEqual(readinessPairIDs.count, expectedUniquePairCount)
        XCTAssertFalse(model.appleLanguagePackGroups.flatMap(\.rows).contains { $0.readiness == .unknown })
        XCTAssertEqual(model.appleLanguagePackSelection.pair, currentPair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertEqual(rowsByPair["th->en"]?.readiness, .needsDownload)
        XCTAssertEqual(rowsByPair["en->th"]?.readiness, .ready)
        XCTAssertEqual(rowsByPair["th->ja"]?.readiness, .unavailable)
    }

    func testPrepareAppleLanguagePackUpdatesGroupedRowsSelectionAndSetupReadiness() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroup(for: .english)
        await model.prepareAppleLanguagePack(for: pair)

        let preparedPairIDs = await languageAvailability.preparedPairIDs()

        XCTAssertTrue(preparedPairIDs.isEmpty)
        XCTAssertEqual(model.appleLanguagePackPreparationRequests.map(\.pair), [pair])
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)

        await languageAvailability.setReadiness(.ready, for: pair)
        await model.finishAppleLanguagePackPreparation(for: pair, result: .success(()))

        let readinessItems = Dictionary(uniqueKeysWithValues: model.readiness.items.map { ($0.kind, $0) })
        let englishRow = try row(
            in: model.appleLanguagePackGroups,
            language: .english,
            pairID: pair.id
        )
        let thaiRow = try row(
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
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.prepareAppleLanguagePack(for: currentPair)
        await model.prepareAppleLanguagePack(for: secondPair)

        let activePairs = Set(model.appleLanguagePackPreparationRequests.map(\.pair))
        let currentRequest = try XCTUnwrap(
            model.appleLanguagePackPreparationRequests.first { $0.pair == currentPair }
        )
        let secondRow = try row(
            in: model.appleLanguagePackGroups,
            language: .japanese,
            pairID: secondPair.id
        )

        XCTAssertEqual(activePairs, [currentPair, secondPair])
        XCTAssertEqual(model.appleLanguagePackSelection.pair, currentPair)
        XCTAssertTrue(model.appleLanguagePackSelection.isPreparing)
        XCTAssertTrue(secondRow.isPreparing)

        await languageAvailability.setReadiness(.ready, for: currentPair)
        await model.finishAppleLanguagePackPreparation(
            for: currentPair,
            requestID: currentRequest.id,
            result: .success(())
        )

        let remainingPairs = model.appleLanguagePackPreparationRequests.map(\.pair)
        let updatedSecondRow = try row(
            in: model.appleLanguagePackGroups,
            language: .japanese,
            pairID: secondPair.id
        )

        XCTAssertEqual(remainingPairs, [secondPair])
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .ready)
        XCTAssertFalse(model.appleLanguagePackSelection.isPreparing)
        XCTAssertTrue(updatedSecondRow.isPreparing)
    }

    func testFinishAppleLanguagePackPreparationKeepsNeedsDownloadMessageAfterFailure() async {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareAppleLanguagePack(for: pair)
        await model.finishAppleLanguagePackPreparation(for: pair, result: .failure(.missingLanguagePack(.apple)))

        XCTAssertTrue(model.appleLanguagePackPreparationRequests.isEmpty)
        XCTAssertEqual(model.appleLanguagePackSelection.pair, pair)
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
        XCTAssertFalse(model.appleLanguagePackSelection.isPreparing)
        XCTAssertEqual(model.appleLanguagePackSelection.message, "Download was not completed. Try Download again.")
    }

    func testStaleAppleLanguagePackPreparationTimesOutAndRechecksReadiness() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: ["en->th": .needsDownload]
        )
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeServices(languageAvailability: languageAvailability)
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
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroup(for: .english)
        await model.prepareAppleLanguagePack(for: pair)
        await model.cancelAppleLanguagePackPreparation(for: pair)

        let preparedPairIDs = await languageAvailability.preparedPairIDs()
        let englishRow = try row(
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
            services: makeServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackSelection()
        await model.prepareSelectedAppleLanguagePack()

        let preparedPairIDs = await languageAvailability.preparedPairIDs()
        XCTAssertNil(model.appleLanguagePackSelection.pair)
        XCTAssertFalse(model.appleLanguagePackSelection.canPrepare)
        XCTAssertTrue(preparedPairIDs.isEmpty)
    }

    private func makeServices(
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

    private func row(
        in groups: [AppleLanguagePackGroup],
        language: TranslationLanguage,
        pairID: String
    ) throws -> AppleLanguagePackReadinessRow {
        let group = try XCTUnwrap(groups.first { $0.language == language })
        return try XCTUnwrap(group.rows.first { $0.id == pairID })
    }
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
