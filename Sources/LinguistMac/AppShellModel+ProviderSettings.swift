import LinguistMacCore

@MainActor
extension AppShellModel {
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

    func refreshAppleLanguagePackSelection() async {
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
        guard !isRefreshingAppleLanguagePackGroups,
              force || !didRefreshAppleLanguagePackGroups
        else {
            return
        }

        isRefreshingAppleLanguagePackGroups = true
        defer {
            isRefreshingAppleLanguagePackGroups = false
        }

        let groupsToCheck = AppleLanguagePackCatalog.groups(from: availableLanguages, settings: settings)
        var readinessByPairID: [String: LanguagePackReadiness] = [:]

        for pair in uniqueAppleLanguagePackPairs(from: groupsToCheck) {
            let readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
            readinessByPairID[pair.id] = readiness
        }

        let currentGroups = AppleLanguagePackCatalog.groups(from: availableLanguages, settings: settings)
        appleLanguagePackGroups = currentGroups.map { group in
            AppleLanguagePackGroup(
                language: group.language,
                rows: group.rows.map { row in
                    appleLanguagePackRow(for: row, readinessByPairID: readinessByPairID)
                },
                isPinned: group.isPinned
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
    }

    func togglePinnedAppleLanguagePackGroup(_ language: TranslationLanguage) {
        if settings.pinnedAppleLanguagePackLanguageIDs.contains(language.id) {
            settings.pinnedAppleLanguagePackLanguageIDs.removeAll { $0 == language.id }
        } else {
            settings.pinnedAppleLanguagePackLanguageIDs.append(language.id)
        }

        settings = settings.sanitized()
        refreshAppleLanguagePackGroupOrder()
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

    private func appleLanguagePackSelectionState(
        pair: AppleLanguagePackPair?,
        readiness: LanguagePackReadiness
    ) -> AppleLanguagePackSelection {
        return AppleLanguagePackSelection(
            pair: pair,
            readiness: readiness
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
                },
                isPinned: group.isPinned
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
            isCurrentPair: currentPair.map { row.pairs.contains($0) } ?? false
        )
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
