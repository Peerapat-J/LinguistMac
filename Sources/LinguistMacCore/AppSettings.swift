public struct AppSettings: Equatable, Sendable {
    public var sourceLanguage: TranslationLanguage
    public var targetLanguage: TranslationLanguage
    public var selectedProviderID: TranslationProviderID
    public var autoCopyEnabled: Bool
    public var launchAtLoginEnabled: Bool
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
        guard !providers.contains(where: { $0.id == selectedProviderID }),
              let fallbackProvider = providers.first
        else {
            return self
        }

        var settings = self
        settings.selectedProviderID = fallbackProvider.id
        return settings
    }
}

public struct KeyboardShortcut: Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: Set<KeyboardModifier>

    public init(key: String, modifiers: Set<KeyboardModifier>) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum KeyboardModifier: String, CaseIterable, Sendable {
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
