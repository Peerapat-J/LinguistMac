import LinguistMacCore
import OSLog

private let appleLanguagePackLogger = Logger(
    subsystem: AppIdentity.linguistMac.bundleIdentifier,
    category: "AppleLanguagePacks"
)

@MainActor
extension AppShellModel {
    static let appleLanguagePackPreparationTimeout: TimeInterval = 120

    var selectableProviders: [TranslationProviderDescriptor] {
        providersSupportingCurrentLanguages(from: availableProviders)
    }

    func setSourceLanguage(_ language: TranslationLanguage) {
        settings.sourceLanguage = language
        sanitizeSelectedProviderForCurrentLanguages()
        refreshAppleLanguagePackSelectionOrder()
    }

    func setTargetLanguage(_ language: TranslationLanguage) {
        settings.targetLanguage = language
        sanitizeSelectedProviderForCurrentLanguages()
        refreshAppleLanguagePackSelectionOrder()
    }

    func settingsWithSupportedProvider() -> AppSettings {
        sanitizeSelectedProviderForCurrentLanguages()
        return settings
    }

    func refreshProviderDescriptors() async {
        let providers = await services.translatorRegistry.availableProviders()
        availableProviders = providers
        await refreshProviderAPIRegionDrafts(for: providers)

        let sanitizedSettings = settings
            .selectingAvailableProvider(from: providers)
            .sanitized()
        if sanitizedSettings != settings {
            settings = sanitizedSettings
            refreshAppleLanguagePackSelectionOrder()
        }

        await refreshReadiness()
        await refreshAppleLanguagePackSelection()
    }

    var appleLanguagePackSupportedLanguages: [TranslationLanguage] {
        AppleLanguagePackCatalog.supportedLanguages(from: availableLanguages)
    }

    func refreshAppleLanguagePackSelection() async {
        await clearStaleAppleLanguagePackPreparationIfNeeded()

        guard let pair = AppleLanguagePackPair.current(settings: settings) else {
            appleLanguagePackSelection = appleLanguagePackSelectionState(pair: nil, readiness: .unknown)
            return
        }

        let readiness = await services.languageAvailability.readiness(
            from: pair.sourceLanguage,
            to: pair.targetLanguage,
            sampleText: nil
        )
        appleLanguagePackSelection = appleLanguagePackSelectionState(pair: pair, readiness: readiness)
    }

    func refreshAppleLanguagePackGroupsIfNeeded() async {
        await refreshAppleLanguagePackGroups(force: false)
    }

    func refreshAppleLanguagePackGroups(force: Bool = true) async {
        await clearStaleAppleLanguagePackPreparationIfNeeded()

        guard !isRefreshingAppleLanguagePackGroups,
              force || !didRefreshAppleLanguagePackGroups
        else {
            return
        }

        isRefreshingAppleLanguagePackGroups = true
        let groups = AppleLanguagePackCatalog.groups(from: availableLanguages, settings: settings)
        var readinessByPairID: [String: LanguagePackReadiness] = [:]

        for pair in uniqueAppleLanguagePackPairs(from: groups) {
            let readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
            readinessByPairID[pair.id] = readiness
        }

        appleLanguagePackGroups = groups.map { group in
            AppleLanguagePackGroup(
                language: group.language,
                rows: group.rows.map { row in
                    appleLanguagePackRow(for: row, readinessByPairID: readinessByPairID)
                }
            )
        }

        if let pair = AppleLanguagePackPair.current(settings: settings) {
            appleLanguagePackSelection = appleLanguagePackSelectionState(
                pair: pair,
                readiness: readinessByPairID[pair.id] ?? .unknown
            )
        } else {
            appleLanguagePackSelection = appleLanguagePackSelectionState(pair: nil, readiness: .unknown)
        }

        didRefreshAppleLanguagePackGroups = true
        isRefreshingAppleLanguagePackGroups = false
    }

    func prepareSelectedAppleLanguagePack() async {
        guard let pair = AppleLanguagePackPair.current(settings: settings) else {
            return
        }

        await prepareAppleLanguagePack(for: pair)
    }

    func refreshAppleLanguagePackGroup(for language: TranslationLanguage) async {
        guard let group = appleLanguagePackGroups.first(where: { $0.language == language }) else {
            return
        }

        var rows: [AppleLanguagePackReadinessRow] = []
        for row in group.rows {
            var readinessByPairID = row.readinessByPairID
            for pair in row.pairs {
                let readiness = await services.languageAvailability.readiness(
                    from: pair.sourceLanguage,
                    to: pair.targetLanguage,
                    sampleText: nil
                )
                readinessByPairID[pair.id] = readiness
                refreshAppleLanguagePackSelectionIfNeeded(for: pair, readiness: readiness)
            }
            rows.append(appleLanguagePackRow(for: row, readinessByPairID: readinessByPairID))
        }

        replaceAppleLanguagePackGroup(
            AppleLanguagePackGroup(language: group.language, rows: rows)
        )
    }

    func prepareAppleLanguagePack(for pair: AppleLanguagePackPair) async {
        await prepareAppleLanguagePacks(for: pair.bidirectionalPairs)
    }

    func prepareAppleLanguagePacks(for pairs: [AppleLanguagePackPair]) async {
        let pairsToPrepare = uniqueAppleLanguagePackPairs(pairs)
            .filter { !preparingAppleLanguagePackIDs.contains($0.id) }
        guard !pairsToPrepare.isEmpty else {
            return
        }

        for pair in pairsToPrepare {
            let request = AppleLanguagePackPreparationRequest(pair: pair)
            preparingAppleLanguagePackIDs.insert(pair.id)
            appleLanguagePackMessages[pair.id] = nil
            appleLanguagePackPreparationRequests.append(request)
            scheduleAppleLanguagePackPreparationTimeout(for: request)
            appleLanguagePackLogger.info("Started Apple language pack preparation for \(pair.id, privacy: .public)")
        }
        refreshAppleLanguagePackSelectionOrder()
    }

    @discardableResult
    func noteAppleLanguagePackPreparationSessionStarted(
        for request: AppleLanguagePackPreparationRequest
    ) -> Bool {
        guard appleLanguagePackPreparationRequests.contains(where: { $0.id == request.id }) else {
            return false
        }

        appleLanguagePackLogger.info("Received Apple translation task session for \(request.pair.id, privacy: .public)")
        return true
    }

    func finishAppleLanguagePackPreparation(
        for pair: AppleLanguagePackPair,
        requestID: UUID? = nil,
        result: Result<Void, TranslationFailure>
    ) async {
        guard let request = activeAppleLanguagePackPreparationRequest(for: pair, requestID: requestID) else {
            return
        }

        activeAppleLanguagePackTimeoutTasks.removeValue(forKey: request.id)?.cancel()

        let readiness: LanguagePackReadiness
        switch result {
        case .success:
            readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
            appleLanguagePackMessages[pair.id] = preparationMessage(for: readiness)
            appleLanguagePackLogger.info(
                "Finished Apple language pack preparation for \(pair.id, privacy: .public)"
            )
            appleLanguagePackLogger.info(
                "Apple language pack readiness is \(readiness.displayText, privacy: .public)"
            )
        case let .failure(error):
            let failureDescription = String(describing: error)
            appleLanguagePackMessages[pair.id] = preparationFailureMessage(from: error)
            readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
            appleLanguagePackLogger.error(
                "Pack preparation failed for \(pair.id, privacy: .public): \(failureDescription, privacy: .public)"
            )
        }

        removeAppleLanguagePackPreparationRequest(request)
        updateAppleLanguagePackRow(for: pair, readiness: readiness)
        await refreshReadiness()
    }

    func cancelAppleLanguagePackPreparation(for pair: AppleLanguagePackPair) async {
        await cancelAppleLanguagePackPreparations(for: pair.bidirectionalPairs)
    }

    func cancelAppleLanguagePackPreparations(for pairs: [AppleLanguagePackPair]) async {
        for pair in uniqueAppleLanguagePackPairs(pairs) {
            guard let request = activeAppleLanguagePackPreparationRequest(for: pair) else {
                continue
            }

            activeAppleLanguagePackTimeoutTasks.removeValue(forKey: request.id)?.cancel()

            let readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
            appleLanguagePackMessages[pair.id] = readiness == .ready
                ? preparationMessage(for: readiness)
                : preparationCancellationMessage()
            removeAppleLanguagePackPreparationRequest(request)
            updateAppleLanguagePackRow(for: pair, readiness: readiness)
            appleLanguagePackLogger.info("Canceled Apple language pack preparation for \(pair.id, privacy: .public)")
        }
        await refreshReadiness()
    }

    func timeoutAppleLanguagePackPreparation(requestID: UUID) async {
        guard let request = appleLanguagePackPreparationRequests.first(where: { $0.id == requestID }),
              preparingAppleLanguagePackIDs.contains(request.pair.id)
        else {
            return
        }

        activeAppleLanguagePackTimeoutTasks[request.id] = nil
        let readiness = await services.languageAvailability.readiness(
            from: request.pair.sourceLanguage,
            to: request.pair.targetLanguage,
            sampleText: nil
        )
        appleLanguagePackMessages[request.pair.id] = readiness == .ready
            ? preparationMessage(for: readiness)
            : preparationTimeoutMessage()
        removeAppleLanguagePackPreparationRequest(request)
        updateAppleLanguagePackRow(for: request.pair, readiness: readiness)
        appleLanguagePackLogger.error(
            "Timed out Apple language pack preparation for \(request.pair.id, privacy: .public)"
        )
        await refreshReadiness()
    }

    func clearStaleAppleLanguagePackPreparationIfNeeded(
        now: Date = Date()
    ) async {
        let staleRequests = appleLanguagePackPreparationRequests.filter {
            now.timeIntervalSince($0.startedAt) >= Self.appleLanguagePackPreparationTimeout
        }

        for request in staleRequests {
            activeAppleLanguagePackTimeoutTasks.removeValue(forKey: request.id)?.cancel()
            await timeoutAppleLanguagePackPreparation(requestID: request.id)
        }
    }

    func refreshAppPreferences() async {
        settings.launchAtLoginEnabled = await services.launchAtLogin.isEnabled()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) async {
        do {
            try await services.launchAtLogin.setEnabled(isEnabled)
            settings.launchAtLoginEnabled = await services.launchAtLogin.isEnabled()
            appPreferenceMessage = isEnabled ? "Launch at Login Enabled." : "Launch at Login Disabled."
        } catch {
            settings.launchAtLoginEnabled = await services.launchAtLogin.isEnabled()
            appPreferenceMessage = "Launch at Login Could Not Be Updated."
        }
    }

    func saveAPIKey(for providerID: TranslationProviderID) async {
        let trimmedKey = providerAPIKeyDrafts[providerID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedRegion = providerAPIRegionDrafts[providerID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.isEmpty else {
            providerConfigurationMessages[providerID] = "Enter an API key before saving."
            return
        }

        do {
            try await services.apiKeyStore.saveAPIKey(trimmedKey, for: providerID)
            if providerID == .microsoftAzure {
                if trimmedRegion.isEmpty {
                    try await services.apiKeyStore.deleteAPIRegion(for: providerID)
                } else {
                    try await services.apiKeyStore.saveAPIRegion(trimmedRegion, for: providerID)
                }
            }
            providerAPIKeyDrafts[providerID] = ""
            if providerID == .microsoftAzure {
                providerAPIRegionDrafts[providerID] = trimmedRegion
            }
            providerConfigurationMessages[providerID] = providerID == .microsoftAzure && !trimmedRegion.isEmpty
                ? "API key and region saved."
                : "API key saved."
            await refreshProviderDescriptors()
        } catch {
            providerConfigurationMessages[providerID] = "API key could not be saved."
        }
    }

    func clearAPIKey(for providerID: TranslationProviderID) async {
        do {
            try await services.apiKeyStore.deleteAPIKey(for: providerID)
            try await services.apiKeyStore.deleteAPIRegion(for: providerID)
            providerAPIKeyDrafts[providerID] = ""
            providerAPIRegionDrafts[providerID] = ""
            providerConfigurationMessages[providerID] = "API key cleared."
            await refreshProviderDescriptors()
        } catch {
            providerConfigurationMessages[providerID] = "API key could not be cleared."
        }
    }

    func testAPIKeyConfiguration(for providerID: TranslationProviderID) async {
        switch await services.apiKeyStore.apiKeyStatus(for: providerID) {
        case .present where providerID == .microsoftAzure:
            let region = await savedAPIRegion(for: providerID)
            providerConfigurationMessages[providerID] = region.isEmpty
                ? "API key is present. Add Azure region if your resource requires it."
                : "API key and region are present. Translation requests can use this provider."
        case .present:
            providerConfigurationMessages[providerID] =
                "API key is present. Translation requests can use this provider."
        case .missing:
            providerConfigurationMessages[providerID] = "No API key is saved for this provider."
        case let .unavailable(reason):
            providerConfigurationMessages[providerID] = "API key status could not be read. \(reason)"
        }
    }

    private func providersSupportingCurrentLanguages(
        from providers: [TranslationProviderDescriptor]
    ) -> [TranslationProviderDescriptor] {
        providers.filter {
            $0.id.supports(sourceLanguage: settings.sourceLanguage, targetLanguage: settings.targetLanguage)
        }
    }

    private func sanitizeSelectedProviderForCurrentLanguages() {
        let sanitizedSettings = settings.selectingAvailableProvider(from: availableProviders)
        if sanitizedSettings != settings {
            settings = sanitizedSettings
        }
    }

    private func refreshAppleLanguagePackSelectionOrder() {
        let currentPair = AppleLanguagePackPair.current(settings: settings)
        let keepsExistingPair = currentPair == appleLanguagePackSelection.pair
        appleLanguagePackSelection = appleLanguagePackSelectionState(
            pair: currentPair,
            readiness: keepsExistingPair ? appleLanguagePackSelection.readiness : .unknown
        )
        refreshAppleLanguagePackGroupOrder()
    }

    private func scheduleAppleLanguagePackPreparationTimeout(
        for request: AppleLanguagePackPreparationRequest
    ) {
        activeAppleLanguagePackTimeoutTasks[request.id]?.cancel()
        activeAppleLanguagePackTimeoutTasks[request.id] = Task { [weak self] in
            let nanoseconds = UInt64(Self.appleLanguagePackPreparationTimeout * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            await self?.timeoutAppleLanguagePackPreparation(requestID: request.id)
        }
    }

    private func activeAppleLanguagePackPreparationRequest(
        for pair: AppleLanguagePackPair,
        requestID: UUID? = nil
    ) -> AppleLanguagePackPreparationRequest? {
        appleLanguagePackPreparationRequests.first { request in
            let matchesRequestID = requestID.map { $0 == request.id } ?? true
            return request.pair == pair && matchesRequestID
        }
    }

    private func removeAppleLanguagePackPreparationRequest(
        _ request: AppleLanguagePackPreparationRequest
    ) {
        appleLanguagePackPreparationRequests.removeAll { $0.id == request.id }
        preparingAppleLanguagePackIDs.remove(request.pair.id)
    }

    private func appleLanguagePackSelectionState(
        pair: AppleLanguagePackPair?,
        readiness: LanguagePackReadiness
    ) -> AppleLanguagePackSelection {
        AppleLanguagePackSelection(
            pair: pair,
            readiness: readiness,
            isPreparing: pair.map { preparingAppleLanguagePackIDs.contains($0.id) } ?? false,
            message: pair.flatMap { appleLanguagePackMessages[$0.id] }
        )
    }

    private func refreshAppleLanguagePackGroupOrder() {
        let existingRows = appleLanguagePackRowsByID()
        let groups = AppleLanguagePackCatalog.groups(from: availableLanguages, settings: settings)
        appleLanguagePackGroups = groups.map { group in
            AppleLanguagePackGroup(
                language: group.language,
                rows: group.rows.map { row in
                    let existingRow = existingRows[row.id] ?? row
                    return appleLanguagePackRow(
                        for: existingRow,
                        readinessByPairID: existingRow.readinessByPairID
                    )
                }
            )
        }
    }

    private func appleLanguagePackRow(
        for row: AppleLanguagePackReadinessRow,
        readinessByPairID: [String: LanguagePackReadiness]
    ) -> AppleLanguagePackReadinessRow {
        let rowReadinessByPairID = Dictionary(
            uniqueKeysWithValues: row.pairs.map { pair in
                (pair.id, readinessByPairID[pair.id] ?? row.readinessByPairID[pair.id] ?? row.readiness)
            }
        )
        let currentPair = AppleLanguagePackPair.current(settings: settings)
        return AppleLanguagePackReadinessRow(
            language: row.language,
            pairedLanguage: row.pairedLanguage,
            pairs: row.pairs,
            readiness: row.readiness,
            readinessByPairID: rowReadinessByPairID,
            isCurrentPair: currentPair.map { row.pairs.contains($0) } ?? false,
            isPreparing: row.pairs.contains { preparingAppleLanguagePackIDs.contains($0.id) },
            message: row.pairs.compactMap { appleLanguagePackMessages[$0.id] }.first
        )
    }

    private func refreshAppleLanguagePackSelectionIfNeeded(
        for pair: AppleLanguagePackPair,
        readiness: LanguagePackReadiness
    ) {
        guard appleLanguagePackSelection.pair == pair else {
            return
        }

        appleLanguagePackSelection = appleLanguagePackSelectionState(pair: pair, readiness: readiness)
    }

    private func updateAppleLanguagePackRow(
        for pair: AppleLanguagePackPair,
        readiness: LanguagePackReadiness
    ) {
        appleLanguagePackGroups = appleLanguagePackGroups.map { group in
            AppleLanguagePackGroup(
                language: group.language,
                rows: group.rows.map { row in
                    guard row.pairs.contains(pair) else {
                        return row
                    }

                    var readinessByPairID = row.readinessByPairID
                    readinessByPairID[pair.id] = readiness
                    return appleLanguagePackRow(for: row, readinessByPairID: readinessByPairID)
                }
            )
        }
        refreshAppleLanguagePackSelectionIfNeeded(for: pair, readiness: readiness)
    }

    private func replaceAppleLanguagePackGroup(_ updatedGroup: AppleLanguagePackGroup) {
        appleLanguagePackGroups = appleLanguagePackGroups.map { group in
            group.id == updatedGroup.id ? updatedGroup : group
        }
    }

    private func appleLanguagePackRowsByID() -> [String: AppleLanguagePackReadinessRow] {
        appleLanguagePackGroups
            .flatMap(\.rows)
            .reduce(into: [:]) { rowsByID, row in
                rowsByID[row.id] = row
            }
    }

    private func uniqueAppleLanguagePackPairs(
        from groups: [AppleLanguagePackGroup]
    ) -> [AppleLanguagePackPair] {
        uniqueAppleLanguagePackPairs(groups.flatMap(\.rows).flatMap(\.pairs))
    }

    private func uniqueAppleLanguagePackPairs(
        _ pairsToDeduplicate: [AppleLanguagePackPair]
    ) -> [AppleLanguagePackPair] {
        var seenPairIDs: Set<String> = []
        var pairs: [AppleLanguagePackPair] = []
        for pair in pairsToDeduplicate where seenPairIDs.insert(pair.id).inserted {
            pairs.append(pair)
        }

        return pairs
    }

    private func preparationMessage(for readiness: LanguagePackReadiness) -> String {
        switch readiness {
        case .ready:
            "Language pack is ready."
        case .needsDownload:
            "Download was not completed. Try Download again."
        case .unavailable:
            "This language pair is not supported by Apple Translation."
        case .unknown:
            "Language pack status could not be checked."
        }
    }

    private func preparationTimeoutMessage() -> String {
        "Download did not finish. Try Download again."
    }

    private func preparationCancellationMessage() -> String {
        "Download canceled. Try Download again."
    }

    private func preparationFailureMessage(from error: Error) -> String {
        guard let failure = error as? TranslationFailure else {
            return "Apple Translation could not prepare this language pair."
        }

        switch failure {
        case .unsupportedLanguagePair:
            return "This language pair is not supported by Apple Translation."
        case .missingLanguagePack:
            return "Download was not completed. Try Download again."
        case .providerUnavailable:
            return "Apple Translation is not available on this Mac."
        default:
            return "Apple Translation could not prepare this language pair."
        }
    }

    private func refreshProviderAPIRegionDrafts(for providers: [TranslationProviderDescriptor]) async {
        guard providers.contains(where: { $0.id == .microsoftAzure }) else {
            providerAPIRegionDrafts.removeValue(forKey: .microsoftAzure)
            return
        }

        let region = await savedAPIRegion(for: .microsoftAzure)
        providerAPIRegionDrafts[.microsoftAzure] = region
    }

    private func savedAPIRegion(for providerID: TranslationProviderID) async -> String {
        do {
            return try await services.apiKeyStore.apiRegion(for: providerID) ?? ""
        } catch {
            return ""
        }
    }
}
