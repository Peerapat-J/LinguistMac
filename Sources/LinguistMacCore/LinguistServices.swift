public struct LinguistServices: Sendable {
    public let screenCapture: any ScreenCaptureServicing
    public let ocr: any OCRServicing
    public let translatorRegistry: any TranslationProviderRegistry
    public let languageAvailability: any LanguageAvailabilityChecking
    public let settingsStore: any AppSettingsStoring
    public let historyStore: any TranslationHistoryStoring
    public let permissionChecker: any PermissionChecking
    public let clipboard: any ClipboardServicing
    public let selectedTextCapture: any SelectedTextCapturing
    public let shortcutRegistry: any ShortcutRegistering

    public init(
        screenCapture: any ScreenCaptureServicing,
        ocr: any OCRServicing,
        translatorRegistry: any TranslationProviderRegistry,
        languageAvailability: any LanguageAvailabilityChecking,
        settingsStore: any AppSettingsStoring,
        historyStore: any TranslationHistoryStoring,
        permissionChecker: any PermissionChecking,
        clipboard: any ClipboardServicing,
        selectedTextCapture: any SelectedTextCapturing,
        shortcutRegistry: any ShortcutRegistering
    ) {
        self.screenCapture = screenCapture
        self.ocr = ocr
        self.translatorRegistry = translatorRegistry
        self.languageAvailability = languageAvailability
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.permissionChecker = permissionChecker
        self.clipboard = clipboard
        self.selectedTextCapture = selectedTextCapture
        self.shortcutRegistry = shortcutRegistry
    }
}
