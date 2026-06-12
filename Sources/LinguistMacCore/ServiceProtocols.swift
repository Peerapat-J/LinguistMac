public protocol ScreenCaptureServicing: Sendable {
    func captureSelection() async throws -> CapturedScreenRegion
}

public protocol OCRServicing: Sendable {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText
}

public protocol TranslationProviding: Sendable {
    var id: TranslationProviderID { get }
    var displayName: String { get }
    var detail: String { get }
    var requiresAPIKey: Bool { get }
    var usesNetwork: Bool { get }
    var privacySummary: String { get }

    func isConfigured() async -> Bool
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

public protocol TranslationProviderRegistry: Sendable {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding
    func availableProviders() async -> [TranslationProviderDescriptor]
}

public extension TranslationProviderRegistry {
    func supportedProviderID(
        preferred providerID: TranslationProviderID,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) async -> TranslationProviderID {
        let providers = await availableProviders()
        let supportedProviders = providers.filter {
            $0.id.supports(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        }

        if supportedProviders.contains(where: { $0.id == providerID }) {
            return providerID
        }

        return supportedProviders.first?.id ?? providerID
    }
}

public protocol LanguageAvailabilityChecking: Sendable {
    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness
}

public protocol AppSettingsStoring: Sendable {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
}

public protocol APIKeyStoring: Sendable {
    func apiKey(for providerID: TranslationProviderID) async throws -> String?
    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws
    func deleteAPIKey(for providerID: TranslationProviderID) async throws
    func containsAPIKey(for providerID: TranslationProviderID) async -> Bool
    func apiRegion(for providerID: TranslationProviderID) async throws -> String?
    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws
    func deleteAPIRegion(for providerID: TranslationProviderID) async throws
}

public protocol LaunchAtLoginServicing: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ isEnabled: Bool) async throws
}

public protocol TranslationHistoryStoring: Sendable {
    func save(_ result: TranslationResult) async throws
    func recent(limit: Int) async throws -> [TranslationResult]
}

public protocol PermissionChecking: Sendable {
    func status(for kind: PermissionKind) async -> PermissionStatus
    func request(for kind: PermissionKind) async -> PermissionStatus
}

public protocol ClipboardServicing: Sendable {
    func readText() async -> String?
    func writeText(_ text: String) async
}

public protocol SelectedTextCapturing: Sendable {
    func captureSelectedText() async throws -> String
}

public protocol ShortcutRegistering: Sendable {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws
    func unregister(_ action: ShortcutAction) async
}

public protocol CloudTranslationClient: Sendable {
    func perform(_ request: CloudTranslationHTTPRequest) async throws -> CloudTranslationHTTPResponse
}
