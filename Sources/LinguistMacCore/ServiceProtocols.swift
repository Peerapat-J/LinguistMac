public protocol ScreenCaptureServicing: Sendable {
    func captureSelection() async throws -> CapturedScreenRegion
}

public protocol OCRServicing: Sendable {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText
}

public protocol TranslationProviding: Sendable {
    var id: TranslationProviderID { get }
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    var usesNetwork: Bool { get }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

public protocol TranslationProviderRegistry: Sendable {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding
    func availableProviders() async -> [TranslationProviderDescriptor]
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

public protocol TranslationHistoryStoring: Sendable {
    func save(_ result: TranslationResult) async throws
    func recent(limit: Int) async throws -> [TranslationResult]
}

public protocol PermissionChecking: Sendable {
    func status(for kind: PermissionKind) async -> PermissionStatus
}

public protocol ClipboardServicing: Sendable {
    func readText() async -> String?
    func writeText(_ text: String) async
}

public protocol ShortcutRegistering: Sendable {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws
    func unregister(_ action: ShortcutAction) async
}
