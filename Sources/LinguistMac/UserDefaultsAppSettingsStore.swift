import Foundation
import LinguistMacCore

actor UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() async throws -> AppSettings {
        Self.loadInitialSettings(from: defaults)
    }

    func saveSettings(_ settings: AppSettings) async throws {
        defaults.saveLinguistSettings(settings)
    }

    static func loadInitialSettings(from defaults: UserDefaults = .standard) -> AppSettings {
        defaults.loadLinguistSettings()
    }
}

private extension UserDefaults {
    private enum Key {
        static let sourceLanguageID = "LinguistMac.settings.sourceLanguageID"
        static let targetLanguageID = "LinguistMac.settings.targetLanguageID"
        static let selectedProviderID = "LinguistMac.settings.selectedProviderID"
        static let autoCopyEnabled = "LinguistMac.settings.autoCopyEnabled"
        static let launchAtLoginEnabled = "LinguistMac.settings.launchAtLoginEnabled"
        static let appLanguage = "LinguistMac.settings.appLanguage"
        static let menuBarIcon = "LinguistMac.settings.menuBarIcon"
        static let doubleCopyTranslationEnabled = "LinguistMac.settings.doubleCopyTranslationEnabled"
        static let dragTranslationEnabled = "LinguistMac.settings.dragTranslationEnabled"
        static let shortcutsEnabled = "LinguistMac.settings.shortcutsEnabled"
        static let screenTranslationShortcutKey = "LinguistMac.settings.screenTranslationShortcut.key"
        static let screenTranslationShortcutModifiers = "LinguistMac.settings.screenTranslationShortcut.modifiers"
        static let textSelectionShortcutKey = "LinguistMac.settings.textSelectionShortcut.key"
        static let textSelectionShortcutModifiers = "LinguistMac.settings.textSelectionShortcut.modifiers"
        static let quickTranslateShortcutKey = "LinguistMac.settings.quickTranslateShortcut.key"
        static let quickTranslateShortcutModifiers = "LinguistMac.settings.quickTranslateShortcut.modifiers"
        static let popupFontSize = "LinguistMac.settings.popupFontSize"
        static let popupFontFamily = "LinguistMac.settings.popupFontFamily"
        static let popupWidth = "LinguistMac.settings.popupWidth"
        static let popupHeight = "LinguistMac.settings.popupHeight"
        static let matchPopupWidthToSelection = "LinguistMac.settings.matchPopupWidthToSelection"
        static let screenTranslationSoundEnabled = "LinguistMac.settings.screenTranslationSoundEnabled"
        static let screenTranslationSoundName = "LinguistMac.settings.screenTranslationSoundName"
        static let screenTranslationNotificationsEnabled =
            "LinguistMac.settings.screenTranslationNotificationsEnabled"
        static let popupOriginX = "LinguistMac.settings.popupOriginX"
        static let popupOriginY = "LinguistMac.settings.popupOriginY"
        static let hasCompletedOnboarding = "LinguistMac.hasCompletedOnboarding"
        static let pinnedAppleLanguagePackLanguageIDs =
            "LinguistMac.settings.pinnedAppleLanguagePackLanguageIDs"
    }

    private struct ShortcutSettings {
        let screenTranslation: KeyboardShortcut
        let textSelection: KeyboardShortcut
        let quickTranslate: KeyboardShortcut
    }

    private struct PresentationSettings {
        let popupFontSize: Double
        let popupFontFamily: String
        let popupWidth: Double
        let popupHeight: Double
        let matchPopupWidthToSelection: Bool
        let screenTranslationSoundEnabled: Bool
        let screenTranslationSoundName: String
        let screenTranslationNotificationsEnabled: Bool
        let popupOriginX: Double?
        let popupOriginY: Double?
    }

    func loadLinguistSettings() -> AppSettings {
        let defaults = AppSettings()
        let source = string(forKey: Key.sourceLanguageID)
            .flatMap(TranslationLanguageCatalog.language(forID:))
            ?? defaults.sourceLanguage
        let target = string(forKey: Key.targetLanguageID)
            .flatMap(TranslationLanguageCatalog.language(forID:))
            ?? defaults.targetLanguage
        let providerID = string(forKey: Key.selectedProviderID)
            .flatMap(TranslationProviderID.knownProvider(rawValue:))
            ?? defaults.selectedProviderID
        let appLanguage = string(forKey: Key.appLanguage)
            .flatMap(AppLanguage.init(rawValue:))
            ?? defaults.appLanguage
        let menuBarIcon = string(forKey: Key.menuBarIcon)
            .flatMap(MenuBarIcon.init(rawValue:))
            ?? defaults.menuBarIcon
        let shortcuts = loadShortcutSettings(defaults: defaults)
        let presentation = loadPresentationSettings(defaults: defaults)

        return AppSettings(
            sourceLanguage: source,
            targetLanguage: target.canBeTargetLanguage ? target : defaults.targetLanguage,
            selectedProviderID: providerID,
            autoCopyEnabled: bool(forKey: Key.autoCopyEnabled, default: defaults.autoCopyEnabled),
            launchAtLoginEnabled: bool(forKey: Key.launchAtLoginEnabled, default: defaults.launchAtLoginEnabled),
            appLanguage: appLanguage,
            menuBarIcon: menuBarIcon,
            doubleCopyTranslationEnabled: bool(
                forKey: Key.doubleCopyTranslationEnabled,
                default: defaults.doubleCopyTranslationEnabled
            ),
            dragTranslationEnabled: bool(forKey: Key.dragTranslationEnabled, default: defaults.dragTranslationEnabled),
            shortcutsEnabled: bool(forKey: Key.shortcutsEnabled, default: defaults.shortcutsEnabled),
            screenTranslationShortcut: shortcuts.screenTranslation,
            textSelectionShortcut: shortcuts.textSelection,
            quickTranslateShortcut: shortcuts.quickTranslate,
            popupFontSize: presentation.popupFontSize,
            popupFontFamily: presentation.popupFontFamily,
            popupWidth: presentation.popupWidth,
            popupHeight: presentation.popupHeight,
            matchPopupWidthToSelection: presentation.matchPopupWidthToSelection,
            screenTranslationSoundEnabled: presentation.screenTranslationSoundEnabled,
            screenTranslationSoundName: presentation.screenTranslationSoundName,
            screenTranslationNotificationsEnabled: presentation.screenTranslationNotificationsEnabled,
            popupOriginX: presentation.popupOriginX,
            popupOriginY: presentation.popupOriginY,
            hasCompletedOnboarding: bool(forKey: Key.hasCompletedOnboarding),
            pinnedAppleLanguagePackLanguageIDs: stringArray(
                forKey: Key.pinnedAppleLanguagePackLanguageIDs
            ) ?? defaults.pinnedAppleLanguagePackLanguageIDs
        ).sanitized()
    }

    private func loadShortcutSettings(defaults: AppSettings) -> ShortcutSettings {
        ShortcutSettings(
            screenTranslation: loadShortcut(
                keyName: Key.screenTranslationShortcutKey,
                modifiersName: Key.screenTranslationShortcutModifiers,
                defaultShortcut: defaults.screenTranslationShortcut
            ),
            textSelection: loadShortcut(
                keyName: Key.textSelectionShortcutKey,
                modifiersName: Key.textSelectionShortcutModifiers,
                defaultShortcut: defaults.textSelectionShortcut
            ),
            quickTranslate: loadShortcut(
                keyName: Key.quickTranslateShortcutKey,
                modifiersName: Key.quickTranslateShortcutModifiers,
                defaultShortcut: defaults.quickTranslateShortcut
            )
        )
    }

    private func loadPresentationSettings(defaults: AppSettings) -> PresentationSettings {
        PresentationSettings(
            popupFontSize: object(forKey: Key.popupFontSize) as? Double ?? defaults.popupFontSize,
            popupFontFamily: string(forKey: Key.popupFontFamily) ?? defaults.popupFontFamily,
            popupWidth: object(forKey: Key.popupWidth) as? Double ?? defaults.popupWidth,
            popupHeight: object(forKey: Key.popupHeight) as? Double ?? defaults.popupHeight,
            matchPopupWidthToSelection: bool(
                forKey: Key.matchPopupWidthToSelection,
                default: defaults.matchPopupWidthToSelection
            ),
            screenTranslationSoundEnabled: bool(
                forKey: Key.screenTranslationSoundEnabled,
                default: defaults.screenTranslationSoundEnabled
            ),
            screenTranslationSoundName: string(forKey: Key.screenTranslationSoundName)
                ?? defaults.screenTranslationSoundName,
            screenTranslationNotificationsEnabled: bool(
                forKey: Key.screenTranslationNotificationsEnabled,
                default: defaults.screenTranslationNotificationsEnabled
            ),
            popupOriginX: object(forKey: Key.popupOriginX) as? Double,
            popupOriginY: object(forKey: Key.popupOriginY) as? Double
        )
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) as? Bool ?? defaultValue
    }

    func saveLinguistSettings(_ settings: AppSettings) {
        set(settings.sourceLanguage.id, forKey: Key.sourceLanguageID)
        set(settings.targetLanguage.id, forKey: Key.targetLanguageID)
        set(settings.selectedProviderID.rawValue, forKey: Key.selectedProviderID)
        set(settings.autoCopyEnabled, forKey: Key.autoCopyEnabled)
        set(settings.launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled)
        set(settings.appLanguage.rawValue, forKey: Key.appLanguage)
        set(settings.menuBarIcon.rawValue, forKey: Key.menuBarIcon)
        set(settings.doubleCopyTranslationEnabled, forKey: Key.doubleCopyTranslationEnabled)
        set(settings.dragTranslationEnabled, forKey: Key.dragTranslationEnabled)
        set(settings.shortcutsEnabled, forKey: Key.shortcutsEnabled)
        saveShortcut(
            settings.screenTranslationShortcut,
            keyName: Key.screenTranslationShortcutKey,
            modifiersName: Key.screenTranslationShortcutModifiers
        )
        saveShortcut(
            settings.textSelectionShortcut,
            keyName: Key.textSelectionShortcutKey,
            modifiersName: Key.textSelectionShortcutModifiers
        )
        saveShortcut(
            settings.quickTranslateShortcut,
            keyName: Key.quickTranslateShortcutKey,
            modifiersName: Key.quickTranslateShortcutModifiers
        )
        set(settings.popupFontSize, forKey: Key.popupFontSize)
        set(settings.popupFontFamily, forKey: Key.popupFontFamily)
        set(settings.popupWidth, forKey: Key.popupWidth)
        set(settings.popupHeight, forKey: Key.popupHeight)
        set(settings.matchPopupWidthToSelection, forKey: Key.matchPopupWidthToSelection)
        set(settings.screenTranslationSoundEnabled, forKey: Key.screenTranslationSoundEnabled)
        set(settings.screenTranslationSoundName, forKey: Key.screenTranslationSoundName)
        set(settings.screenTranslationNotificationsEnabled, forKey: Key.screenTranslationNotificationsEnabled)
        if let popupOriginX = settings.popupOriginX {
            set(popupOriginX, forKey: Key.popupOriginX)
        } else {
            removeObject(forKey: Key.popupOriginX)
        }
        if let popupOriginY = settings.popupOriginY {
            set(popupOriginY, forKey: Key.popupOriginY)
        } else {
            removeObject(forKey: Key.popupOriginY)
        }
        set(settings.hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        set(settings.pinnedAppleLanguagePackLanguageIDs, forKey: Key.pinnedAppleLanguagePackLanguageIDs)
    }

    private func loadShortcut(
        keyName: String,
        modifiersName: String,
        defaultShortcut: KeyboardShortcut
    ) -> KeyboardShortcut {
        guard let key = string(forKey: keyName), !key.isEmpty else {
            return defaultShortcut
        }

        let modifiers = Set(
            (stringArray(forKey: modifiersName) ?? [])
                .compactMap(KeyboardModifier.init(rawValue:))
        )
        return KeyboardShortcut(key: key, modifiers: modifiers)
    }

    private func saveShortcut(
        _ shortcut: KeyboardShortcut,
        keyName: String,
        modifiersName: String
    ) {
        set(shortcut.key, forKey: keyName)
        set(
            shortcut.modifiers
                .map(\.rawValue)
                .sorted(),
            forKey: modifiersName
        )
    }
}
