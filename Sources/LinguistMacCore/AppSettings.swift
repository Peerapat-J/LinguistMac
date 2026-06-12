public struct AppSettings: Codable, Equatable, Sendable {
    public var sourceLanguage: TranslationLanguage
    public var targetLanguage: TranslationLanguage
    public var selectedProviderID: TranslationProviderID
    public var autoCopyEnabled: Bool
    public var launchAtLoginEnabled: Bool
    public var appLanguage: AppLanguage
    public var doubleCopyTranslationEnabled: Bool
    public var dragTranslationEnabled: Bool
    public var screenTranslationShortcut: KeyboardShortcut
    public var textSelectionShortcut: KeyboardShortcut
    public var quickTranslateShortcut: KeyboardShortcut
    public var popupFontSize: Double
    public var popupWidth: Double
    public var matchPopupWidthToSelection: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        sourceLanguage: TranslationLanguage = .autoDetect,
        targetLanguage: TranslationLanguage = .english,
        selectedProviderID: TranslationProviderID = .apple,
        autoCopyEnabled: Bool = false,
        launchAtLoginEnabled: Bool = false,
        appLanguage: AppLanguage = .system,
        doubleCopyTranslationEnabled: Bool = false,
        dragTranslationEnabled: Bool = false,
        screenTranslationShortcut: KeyboardShortcut = .screenTranslationDefault,
        textSelectionShortcut: KeyboardShortcut = .textSelectionDefault,
        quickTranslateShortcut: KeyboardShortcut = .quickTranslateDefault,
        popupFontSize: Double = 15,
        popupWidth: Double = 420,
        matchPopupWidthToSelection: Bool = true,
        hasCompletedOnboarding: Bool = false
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.selectedProviderID = selectedProviderID
        self.autoCopyEnabled = autoCopyEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.appLanguage = appLanguage
        self.doubleCopyTranslationEnabled = doubleCopyTranslationEnabled
        self.dragTranslationEnabled = dragTranslationEnabled
        self.screenTranslationShortcut = screenTranslationShortcut
        self.textSelectionShortcut = textSelectionShortcut
        self.quickTranslateShortcut = quickTranslateShortcut
        self.popupFontSize = popupFontSize
        self.popupWidth = popupWidth
        self.matchPopupWidthToSelection = matchPopupWidthToSelection
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

public extension AppSettings {
    func selectingAvailableProvider(from providers: [TranslationProviderDescriptor]) -> AppSettings {
        let supportedProviders = providers.filter {
            $0.id.supports(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        }
        guard !supportedProviders.contains(where: { $0.id == selectedProviderID }),
              let fallbackProvider = supportedProviders.first ?? providers.first
        else {
            return self
        }

        var settings = self
        settings.selectedProviderID = fallbackProvider.id
        return settings
    }

    func sanitized() -> AppSettings {
        var settings = self
        if !settings.targetLanguage.canBeTargetLanguage {
            settings.targetLanguage = .english
        }
        settings.popupFontSize = min(max(settings.popupFontSize, 12), 22)
        settings.popupWidth = min(max(settings.popupWidth, 320), 720)
        return settings
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case korean

    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .english:
            "English"
        case .korean:
            "Korean"
        }
    }
}

public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: Set<KeyboardModifier>

    public init(key: String, modifiers: Set<KeyboardModifier>) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum KeyboardModifier: String, CaseIterable, Codable, Sendable {
    case command
    case control
    case option
    case shift
}

public extension KeyboardShortcut {
    static let screenTranslationDefault = KeyboardShortcut(
        key: "E",
        modifiers: [.command]
    )

    static let quickTranslateDefault = KeyboardShortcut(
        key: "E",
        modifiers: [.command, .shift]
    )

    static let textSelectionDefault = KeyboardShortcut(
        key: "Z",
        modifiers: [.command, .option]
    )
}
