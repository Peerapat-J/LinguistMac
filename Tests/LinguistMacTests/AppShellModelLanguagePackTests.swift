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
            "Preparing",
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

    func testRefreshAppleLanguagePackGroupsForLanguagesChecksOnlyRequestedLanguagePairs() async throws {
        let languageAvailability = LanguagePackTestAvailabilityChecker(
            readinessByPair: [
                "th->en": .needsDownload,
                "en->th": .ready,
                "th->ja": .unavailable
            ]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english),
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )
        let supportedLanguages = AppleLanguagePackCatalog.supportedLanguages(
            from: TranslationLanguageCatalog.defaultLanguages
        )
        let expectedThaiPairCount = (supportedLanguages.count - 1) * 2

        await model.refreshAppleLanguagePackGroups(for: [.thai])

        let readinessPairIDs = await languageAvailability.readinessPairIDs()
        let thaiEnglishRow = try languagePackRow(in: model.appleLanguagePackGroups, language: .thai, pairID: "th->en")
        let thaiJapaneseRow = try languagePackRow(in: model.appleLanguagePackGroups, language: .thai, pairID: "th->ja")

        XCTAssertEqual(Set(readinessPairIDs).count, expectedThaiPairCount)
        XCTAssertEqual(readinessPairIDs.count, expectedThaiPairCount)
        XCTAssertTrue(readinessPairIDs.allSatisfy { $0.contains("th") })
        XCTAssertEqual(model.appleLanguagePackSelection.readiness, .needsDownload)
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

    func testRefreshAppleLanguagePackGroupsKeepsPinChangesMadeDuringRefresh() async throws {
        let languageAvailability = BlockingLanguagePackChecker()
        let model = AppShellModel(
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        let refreshTask = Task {
            await model.refreshAppleLanguagePackGroups()
        }
        await languageAvailability.waitUntilFirstReadinessCall()

        model.togglePinnedAppleLanguagePackGroup(.thai)
        XCTAssertEqual(model.appleLanguagePackGroups.first?.language, .thai)

        await languageAvailability.resumeFirstReadinessCall()
        await refreshTask.value

        let thaiGroup = try XCTUnwrap(model.appleLanguagePackGroups.first)
        XCTAssertEqual(model.settings.pinnedAppleLanguagePackLanguageIDs, ["th"])
        XCTAssertEqual(thaiGroup.language, .thai)
        XCTAssertTrue(thaiGroup.isPinned)
    }

    func testRefreshAppleLanguagePackGroupsRunsQueuedRefreshAfterOverlap() async {
        let languageAvailability = BlockingLanguagePackChecker()
        let model = AppShellModel(
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )
        let supportedLanguageCount = AppleLanguagePackCatalog
            .supportedLanguages(from: TranslationLanguageCatalog.defaultLanguages)
            .count
        let expectedUniquePairCount = supportedLanguageCount * (supportedLanguageCount - 1)

        let refreshTask = Task {
            await model.refreshAppleLanguagePackGroups()
        }
        await languageAvailability.waitUntilFirstReadinessCall()

        await model.refreshAppleLanguagePackGroups(force: true)
        await languageAvailability.resumeFirstReadinessCall()
        await refreshTask.value

        let readinessPairIDs = await languageAvailability.readinessPairIDs()
        XCTAssertEqual(readinessPairIDs.count, expectedUniquePairCount * 2)
    }

    func testRefreshAppleLanguagePackGroupsChecksReadinessConcurrently() async {
        let languageAvailability = ConcurrentLanguagePackChecker()
        let model = AppShellModel(
            services: makeLanguagePackTestServices(languageAvailability: languageAvailability)
        )

        await model.refreshAppleLanguagePackGroups(for: [.thai])

        let maximumActiveReadinessCalls = await languageAvailability.maximumActiveReadinessCalls()
        XCTAssertGreaterThan(maximumActiveReadinessCalls, 1)
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

@MainActor
final class PopupLanguageSelectionTests: XCTestCase {
    func testSelectingPopupTargetPersistsPairAndRetranslatesOriginalText() async throws {
        let provider = PopupTranslationTestProvider()
        let historyStore = PopupTranslationHistoryStore()
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .japanese),
            services: makePopupTranslationServices(
                provider: provider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(
            popupResult(source: .english, target: .japanese),
            showsOriginal: true
        )

        model.selectPopupTargetLanguage(.thai)
        let task = try XCTUnwrap(model.activePopupTranslationTask)
        await task.value

        XCTAssertEqual(model.settings.sourceLanguage, .english)
        XCTAssertEqual(model.settings.targetLanguage, .thai)
        guard case let .success(result, showsOriginal, _) = model.popupState else {
            return XCTFail("Expected the popup retranslation to complete.")
        }
        XCTAssertEqual(result.originalText, "hello")
        XCTAssertEqual(result.translatedText, "translated-th")
        XCTAssertEqual(result.request.targetLanguage, .thai)
        XCTAssertTrue(showsOriginal)

        let requests = await provider.capturedRequests()
        XCTAssertEqual(requests.map(\.text), ["hello"])
        XCTAssertEqual(requests.map(\.targetLanguage), [.thai])
        let savedResults = await historyStore.capturedResults()
        XCTAssertEqual(savedResults.map(\.translatedText), ["translated-th"])
    }

    func testLatestPopupLanguageSelectionWinsWhenEarlierProviderCallFinishesLate() async throws {
        let provider = GatedPopupTranslationTestProvider()
        let historyStore = PopupTranslationHistoryStore()
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .japanese),
            services: makePopupTranslationServices(
                provider: provider,
                historyStore: historyStore
            )
        )
        model.popupState = .success(
            popupResult(source: .english, target: .japanese),
            showsOriginal: false
        )

        model.selectPopupTargetLanguage(.thai)
        let firstTask = try XCTUnwrap(model.activePopupTranslationTask)
        await provider.waitUntilFirstRequestStarts()

        model.selectPopupTargetLanguage(.japanese)
        let secondTask = try XCTUnwrap(model.activePopupTranslationTask)
        await secondTask.value
        await provider.releaseFirstRequest()
        await firstTask.value

        guard case let .success(result, showsOriginal, _) = model.popupState else {
            return XCTFail("Expected the latest popup translation to remain visible.")
        }
        XCTAssertEqual(result.request.targetLanguage, .japanese)
        XCTAssertEqual(result.translatedText, "translated-ja")
        XCTAssertFalse(showsOriginal)
        let savedResults = await historyStore.capturedResults()
        XCTAssertEqual(savedResults.map(\.translatedText), ["translated-ja"])
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

private func makePopupTranslationServices(
    provider: any TranslationProviding,
    historyStore: any TranslationHistoryStoring
) -> LinguistServices {
    let noOpService = SetupPermissionNoOpService()
    return LinguistServices(
        screenCapture: noOpService,
        ocr: noOpService,
        translatorRegistry: PopupTranslationTestRegistry(provider: provider),
        languageAvailability: noOpService,
        settingsStore: noOpService,
        apiKeyStore: noOpService,
        launchAtLogin: noOpService,
        historyStore: historyStore,
        permissionChecker: noOpService,
        clipboard: noOpService,
        selectedTextCapture: noOpService,
        shortcutRegistry: noOpService,
        screenTranslationSoundPlayer: NoOpScreenTranslationSoundPlayer(),
        screenTranslationNotifier: NoOpScreenTranslationNotifier()
    )
}

private func popupResult(
    source: TranslationLanguage,
    target: TranslationLanguage
) -> TranslationResult {
    TranslationResult(
        request: TranslationRequest(
            text: "hello",
            sourceLanguage: source,
            targetLanguage: target,
            inputMode: .quickTranslate,
            providerID: .apple
        ),
        translatedText: "translated-\(target.id)"
    )
}

private struct PopupTranslationTestRegistry: TranslationProviderRegistry {
    let provider: any TranslationProviding

    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        _ = id
        return provider
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        [
            TranslationProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                requiresAPIKey: false,
                usesNetwork: provider.usesNetwork
            )
        ]
    }
}

private actor PopupTranslationTestProvider: TranslationProviding {
    let id = TranslationProviderID.apple
    let displayName = "Popup Test Provider"
    let detail = "Popup language selection tests"
    let requiresAPIKey = false
    let usesNetwork = true
    let privacySummary = "Test provider"
    private var requests: [TranslationRequest] = []

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        return TranslationResult(
            request: request,
            translatedText: "translated-\(request.targetLanguage.id)"
        )
    }

    func capturedRequests() -> [TranslationRequest] {
        requests
    }
}

private actor GatedPopupTranslationTestProvider: TranslationProviding {
    let id = TranslationProviderID.apple
    let displayName = "Gated Popup Test Provider"
    let detail = "Popup request ordering tests"
    let requiresAPIKey = false
    let usesNetwork = true
    let privacySummary = "Test provider"
    private var requests: [TranslationRequest] = []
    private var firstRequestStarted = false
    private var firstRequestStartContinuation: CheckedContinuation<Void, Never>?
    private var firstRequestReleaseContinuation: CheckedContinuation<Void, Never>?

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        if requests.count == 1 {
            firstRequestStarted = true
            firstRequestStartContinuation?.resume()
            firstRequestStartContinuation = nil
            await withCheckedContinuation { continuation in
                firstRequestReleaseContinuation = continuation
            }
        }

        return TranslationResult(
            request: request,
            translatedText: "translated-\(request.targetLanguage.id)"
        )
    }

    func waitUntilFirstRequestStarts() async {
        guard !firstRequestStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            firstRequestStartContinuation = continuation
        }
    }

    func releaseFirstRequest() {
        firstRequestReleaseContinuation?.resume()
        firstRequestReleaseContinuation = nil
    }
}

private actor PopupTranslationHistoryStore: TranslationHistoryStoring {
    private var results: [TranslationResult] = []

    func save(_ result: TranslationResult) async throws {
        results.append(result)
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        Array(results.suffix(limit))
    }

    func capturedResults() -> [TranslationResult] {
        results
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

private actor BlockingLanguagePackChecker: LanguageAvailabilityChecking {
    private var didBlock = false
    private var didBlockContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var readinessPairs: [String] = []

    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        _ = sampleText
        readinessPairs.append("\(source.id)->\(target.id)")

        if !didBlock {
            didBlock = true
            didBlockContinuation?.resume()
            didBlockContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        return .ready
    }

    func prepareLanguagePack(
        from source: TranslationLanguage,
        to target: TranslationLanguage
    ) async throws -> LanguagePackReadiness {
        _ = source
        _ = target
        return .ready
    }

    func waitUntilFirstReadinessCall() async {
        guard !didBlock else {
            return
        }

        await withCheckedContinuation { continuation in
            didBlockContinuation = continuation
        }
    }

    func resumeFirstReadinessCall() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func readinessPairIDs() -> [String] {
        readinessPairs
    }
}

private actor ConcurrentLanguagePackChecker: LanguageAvailabilityChecking {
    private var activeReadinessCallCount = 0
    private var maxActiveReadinessCallCount = 0

    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        _ = source
        _ = target
        _ = sampleText
        activeReadinessCallCount += 1
        maxActiveReadinessCallCount = max(maxActiveReadinessCallCount, activeReadinessCallCount)

        do {
            try await Task.sleep(nanoseconds: 10_000_000)
        } catch {
            activeReadinessCallCount -= 1
            return .unknown
        }

        activeReadinessCallCount -= 1
        return .ready
    }

    func prepareLanguagePack(
        from source: TranslationLanguage,
        to target: TranslationLanguage
    ) async throws -> LanguagePackReadiness {
        _ = source
        _ = target
        return .ready
    }

    func maximumActiveReadinessCalls() -> Int {
        maxActiveReadinessCallCount
    }
}
