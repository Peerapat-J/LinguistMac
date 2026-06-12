import LinguistMacCore

@MainActor
extension AppShellModel {
    var selectableProviders: [TranslationProviderDescriptor] {
        providersSupportingCurrentLanguages(from: availableProviders)
    }

    func setSourceLanguage(_ language: TranslationLanguage) {
        settings.sourceLanguage = language
        sanitizeSelectedProviderForCurrentLanguages()
    }

    func setTargetLanguage(_ language: TranslationLanguage) {
        settings.targetLanguage = language
        sanitizeSelectedProviderForCurrentLanguages()
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
        }

        await refreshReadiness()
    }

    func refreshAppPreferences() async {
        settings.launchAtLoginEnabled = await services.launchAtLogin.isEnabled()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) async {
        do {
            try await services.launchAtLogin.setEnabled(isEnabled)
            settings.launchAtLoginEnabled = await services.launchAtLogin.isEnabled()
            appPreferenceMessage = isEnabled ? "Launch at login enabled." : "Launch at login disabled."
        } catch {
            settings.launchAtLoginEnabled = await services.launchAtLogin.isEnabled()
            appPreferenceMessage = "Launch at login could not be updated."
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
            let region = await (try? services.apiKeyStore.apiRegion(for: providerID)) ?? ""
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

    private func refreshProviderAPIRegionDrafts(for providers: [TranslationProviderDescriptor]) async {
        guard providers.contains(where: { $0.id == .microsoftAzure }) else {
            providerAPIRegionDrafts.removeValue(forKey: .microsoftAzure)
            return
        }

        let region = await (try? services.apiKeyStore.apiRegion(for: .microsoftAzure)) ?? ""
        providerAPIRegionDrafts[.microsoftAzure] = region
    }
}
