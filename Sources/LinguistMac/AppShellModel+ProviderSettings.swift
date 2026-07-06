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

    var appleLanguagePackSupportedLanguages: [TranslationLanguage] {
        AppleLanguagePackCatalog.supportedLanguages(from: availableLanguages)
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
                    appleLanguagePackRow(
                        for: row.pair,
                        readiness: readinessByPairID[row.id] ?? row.readiness
                    )
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
            let readiness = await services.languageAvailability.readiness(
                from: row.pair.sourceLanguage,
                to: row.pair.targetLanguage,
                sampleText: nil
            )
            rows.append(appleLanguagePackRow(for: row.pair, readiness: readiness))
            refreshAppleLanguagePackSelectionIfNeeded(for: row.pair, readiness: readiness)
        }

        replaceAppleLanguagePackGroup(
            AppleLanguagePackGroup(language: group.language, rows: rows)
        )
    }

    func prepareAppleLanguagePack(for pair: AppleLanguagePackPair) async {
        guard preparingAppleLanguagePackID == nil else {
            return
        }

        preparingAppleLanguagePackID = pair.id
        appleLanguagePackMessages[pair.id] = nil
        appleLanguagePackPreparationRequest = AppleLanguagePackPreparationRequest(pair: pair)
        refreshAppleLanguagePackSelectionOrder()
    }

    func finishAppleLanguagePackPreparation(
        for pair: AppleLanguagePackPair,
        result: Result<Void, TranslationFailure>
    ) async {
        guard preparingAppleLanguagePackID == pair.id else {
            return
        }

        let readiness: LanguagePackReadiness
        switch result {
        case .success:
            readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
            appleLanguagePackMessages[pair.id] = preparationMessage(for: readiness)
        case let .failure(error):
            appleLanguagePackMessages[pair.id] = preparationFailureMessage(from: error)
            readiness = await services.languageAvailability.readiness(
                from: pair.sourceLanguage,
                to: pair.targetLanguage,
                sampleText: nil
            )
        }

        preparingAppleLanguagePackID = nil
        appleLanguagePackPreparationRequest = nil
        updateAppleLanguagePackRow(for: pair, readiness: readiness)
        await refreshReadiness()
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
        AppleLanguagePackSelection(
            pair: pair,
            readiness: readiness,
            isPreparing: pair?.id == preparingAppleLanguagePackID,
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
                    appleLanguagePackRow(
                        for: row.pair,
                        readiness: existingRows[row.id]?.readiness ?? row.readiness
                    )
                }
            )
        }
    }

    private func appleLanguagePackRow(
        for pair: AppleLanguagePackPair,
        readiness: LanguagePackReadiness
    ) -> AppleLanguagePackReadinessRow {
        AppleLanguagePackReadinessRow(
            pair: pair,
            readiness: readiness,
            isCurrentPair: pair == AppleLanguagePackPair.current(settings: settings),
            isPreparing: pair.id == preparingAppleLanguagePackID,
            message: appleLanguagePackMessages[pair.id]
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
                    row.pair == pair ? appleLanguagePackRow(for: pair, readiness: readiness) : row
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
        var seenPairIDs: Set<String> = []
        var pairs: [AppleLanguagePackPair] = []
        for row in groups.flatMap(\.rows) where seenPairIDs.insert(row.id).inserted {
            pairs.append(row.pair)
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
