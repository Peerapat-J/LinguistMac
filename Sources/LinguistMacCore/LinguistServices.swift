public struct LinguistServices: Sendable {
    public let screenCapture: any ScreenCaptureServicing
    public let ocr: any OCRServicing
    public let translatorRegistry: any TranslationProviderRegistry
    public let languageAvailability: any LanguageAvailabilityChecking
    public let settingsStore: any AppSettingsStoring
    public let apiKeyStore: any APIKeyStoring
    public let launchAtLogin: any LaunchAtLoginServicing
    public let historyStore: any TranslationHistoryStoring
    public let permissionChecker: any PermissionChecking
    public let clipboard: any ClipboardServicing
    public let selectedTextCapture: any SelectedTextCapturing
    public let shortcutRegistry: any ShortcutRegistering
    public let wordLookupProvider: any WordLookupProviding

    public init(
        screenCapture: any ScreenCaptureServicing,
        ocr: any OCRServicing,
        translatorRegistry: any TranslationProviderRegistry,
        languageAvailability: any LanguageAvailabilityChecking,
        settingsStore: any AppSettingsStoring,
        apiKeyStore: any APIKeyStoring,
        launchAtLogin: any LaunchAtLoginServicing,
        historyStore: any TranslationHistoryStoring,
        permissionChecker: any PermissionChecking,
        clipboard: any ClipboardServicing,
        selectedTextCapture: any SelectedTextCapturing,
        shortcutRegistry: any ShortcutRegistering,
        wordLookupProvider: any WordLookupProviding = UnavailableWordLookupProvider()
    ) {
        self.screenCapture = screenCapture
        self.ocr = ocr
        self.translatorRegistry = translatorRegistry
        self.languageAvailability = languageAvailability
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.launchAtLogin = launchAtLogin
        self.historyStore = historyStore
        self.permissionChecker = permissionChecker
        self.clipboard = clipboard
        self.selectedTextCapture = selectedTextCapture
        self.shortcutRegistry = shortcutRegistry
        self.wordLookupProvider = wordLookupProvider
    }
}
