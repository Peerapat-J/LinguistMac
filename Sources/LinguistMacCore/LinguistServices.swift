public struct LinguistServices: Sendable {
    public let screenCapture: any ScreenCaptureServicing
    public let ocr: any OCRServicing
    public let translatorRegistry: any TranslationProviderRegistry
    public let settingsStore: any AppSettingsStoring
    public let historyStore: any TranslationHistoryStoring
    public let permissionChecker: any PermissionChecking
    public let clipboard: any ClipboardServicing
    public let shortcutRegistry: any ShortcutRegistering

    public init(
        screenCapture: any ScreenCaptureServicing,
        ocr: any OCRServicing,
        translatorRegistry: any TranslationProviderRegistry,
        settingsStore: any AppSettingsStoring,
        historyStore: any TranslationHistoryStoring,
        permissionChecker: any PermissionChecking,
        clipboard: any ClipboardServicing,
        shortcutRegistry: any ShortcutRegistering
    ) {
        self.screenCapture = screenCapture
        self.ocr = ocr
        self.translatorRegistry = translatorRegistry
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.permissionChecker = permissionChecker
        self.clipboard = clipboard
        self.shortcutRegistry = shortcutRegistry
    }
}
