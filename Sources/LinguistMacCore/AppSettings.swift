import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var sourceLanguage: TranslationLanguage
    public var targetLanguage: TranslationLanguage
    public var selectedProviderID: TranslationProviderID
    public var autoCopyEnabled: Bool
    public var launchAtLoginEnabled: Bool
    public var appLanguage: AppLanguage
    public var menuBarIcon: MenuBarIcon
    public var doubleCopyTranslationEnabled: Bool
    public var dragTranslationEnabled: Bool
    public var shortcutsEnabled: Bool
    public var screenTranslationShortcut: KeyboardShortcut
    public var textSelectionShortcut: KeyboardShortcut
    public var quickTranslateShortcut: KeyboardShortcut
    public var popupFontSize: Double
    public var popupFontFamily: String
    public var popupWidth: Double
    public var popupHeight: Double
    public var matchPopupWidthToSelection: Bool
    public var screenTranslationSoundEnabled: Bool
    public var screenTranslationSoundName: String
    public var screenTranslationNotificationsEnabled: Bool
    public var popupOriginX: Double?
    public var popupOriginY: Double?
    public var hasCompletedOnboarding: Bool
    public var pinnedAppleLanguagePackLanguageIDs: [String]

    public init(
        sourceLanguage: TranslationLanguage = .autoDetect,
        targetLanguage: TranslationLanguage = .english,
        selectedProviderID: TranslationProviderID = .apple,
        autoCopyEnabled: Bool = false,
        launchAtLoginEnabled: Bool = false,
        appLanguage: AppLanguage = .system,
        menuBarIcon: MenuBarIcon = .default,
        doubleCopyTranslationEnabled: Bool = false,
        dragTranslationEnabled: Bool = false,
        shortcutsEnabled: Bool = true,
        screenTranslationShortcut: KeyboardShortcut = .screenTranslationDefault,
        textSelectionShortcut: KeyboardShortcut = .textSelectionDefault,
        quickTranslateShortcut: KeyboardShortcut = .quickTranslateDefault,
        popupFontSize: Double = 15,
        popupFontFamily: String = "",
        popupWidth: Double = 420,
        popupHeight: Double = 320,
        matchPopupWidthToSelection: Bool = true,
        screenTranslationSoundEnabled: Bool = false,
        screenTranslationSoundName: String = ScreenTranslationSoundPolicy.preferredDefaultSoundName,
        screenTranslationNotificationsEnabled: Bool = false,
        popupOriginX: Double? = nil,
        popupOriginY: Double? = nil,
        hasCompletedOnboarding: Bool = false,
        pinnedAppleLanguagePackLanguageIDs: [String] = []
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.selectedProviderID = selectedProviderID
        self.autoCopyEnabled = autoCopyEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.appLanguage = appLanguage
        self.menuBarIcon = menuBarIcon
        self.doubleCopyTranslationEnabled = doubleCopyTranslationEnabled
        self.dragTranslationEnabled = dragTranslationEnabled
        self.shortcutsEnabled = shortcutsEnabled
        self.screenTranslationShortcut = screenTranslationShortcut
        self.textSelectionShortcut = textSelectionShortcut
        self.quickTranslateShortcut = quickTranslateShortcut
        self.popupFontSize = popupFontSize
        self.popupFontFamily = popupFontFamily
        self.popupWidth = popupWidth
        self.popupHeight = popupHeight
        self.matchPopupWidthToSelection = matchPopupWidthToSelection
        self.screenTranslationSoundEnabled = screenTranslationSoundEnabled
        self.screenTranslationSoundName = screenTranslationSoundName
        self.screenTranslationNotificationsEnabled = screenTranslationNotificationsEnabled
        self.popupOriginX = popupOriginX
        self.popupOriginY = popupOriginY
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.pinnedAppleLanguagePackLanguageIDs = pinnedAppleLanguagePackLanguageIDs
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
        settings.popupHeight = min(max(settings.popupHeight, 240), 640)
        let supportedLanguageIDs = Set(
            TranslationLanguageCatalog.defaultLanguages
                .filter { !$0.supportsAutoDetect }
                .map(\.id)
        )
        var seenPinnedLanguageIDs: Set<String> = []
        settings.pinnedAppleLanguagePackLanguageIDs = settings.pinnedAppleLanguagePackLanguageIDs.filter {
            supportedLanguageIDs.contains($0) && seenPinnedLanguageIDs.insert($0).inserted
        }
        return settings
    }
}

public enum ScreenTranslationSoundPolicy {
    public static let preferredDefaultSoundName = "Glass"

    public static func defaultSoundName(from soundNames: [String]) -> String {
        if soundNames.contains(preferredDefaultSoundName) {
            return preferredDefaultSoundName
        }

        return soundNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first
            ?? preferredDefaultSoundName
    }

    public static func resolvedSoundName(_ soundName: String, from soundNames: [String]) -> String {
        guard !soundNames.isEmpty else {
            return preferredDefaultSoundName
        }
        guard soundNames.contains(soundName) else {
            return defaultSoundName(from: soundNames)
        }

        return soundName
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

    public var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .korean:
            "ko"
        }
    }

    public var locale: Locale {
        guard let localeIdentifier else {
            return .autoupdatingCurrent
        }

        return Locale(identifier: localeIdentifier)
    }

    public var appleLanguages: [String]? {
        localeIdentifier.map { [$0] }
    }
}

public enum MenuBarIcon: String, CaseIterable, Codable, Sendable {
    case asterisk
    case lassoBadgeSparkles = "lasso.badge.sparkles"
    case timelapse
    case aqiMedium = "aqi.medium"
    case appSpecular = "app.specular"
    case handRaysFill = "hand.rays.fill"
    case bonjour
    case textQuote = "text.quote"
    case characterPhonetic = "character.phonetic"
    case characterMagnify = "character.magnify"
    case tSquareFill = "t.square.fill"

    public static let `default`: MenuBarIcon = .asterisk

    public var systemImage: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .asterisk:
            "Asterisk"
        case .lassoBadgeSparkles:
            "Lasso"
        case .timelapse:
            "Timelapse"
        case .aqiMedium:
            "Air Quality"
        case .appSpecular:
            "App Icon"
        case .handRaysFill:
            "Hand Rays"
        case .bonjour:
            "Bonjour"
        case .textQuote:
            "Text Quote"
        case .characterPhonetic:
            "Phonetic"
        case .characterMagnify:
            "Magnifier"
        case .tSquareFill:
            "T-Square"
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
