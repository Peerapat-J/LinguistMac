import ApplicationServices
import CoreGraphics
import Foundation
import LinguistMacCore

enum LiveLinguistServices {
    @MainActor
    static func make() -> LinguistServices {
        let settingsStore = UserDefaultsAppSettingsStore()

        return LinguistServices(
            screenCapture: ScreenCaptureKitScreenCaptureService(),
            ocr: AppleVisionOCRService(),
            translatorRegistry: DefaultTranslationProviderRegistry(),
            languageAvailability: AppleTranslationAvailabilityService(),
            settingsStore: settingsStore,
            historyStore: InMemoryRecentTranslationStore(),
            permissionChecker: SystemPermissionChecker(),
            clipboard: SystemClipboardService(),
            shortcutRegistry: NoOpShortcutRegistry()
        )
    }
}

struct SystemPermissionChecker: PermissionChecking {
    func status(for kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .notDetermined
        case .keychain, .network:
            .notDetermined
        }
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .screenRecording:
            CGRequestScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .notDetermined
        case .keychain, .network:
            .notDetermined
        }
    }
}

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

actor InMemoryRecentTranslationStore: TranslationHistoryStoring {
    private var results: [TranslationResult] = []

    func save(_ result: TranslationResult) async throws {
        results.insert(result, at: 0)
        results = Array(results.prefix(10))
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        Array(results.prefix(limit))
    }
}

actor NoOpShortcutRegistry: ShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        _ = shortcut
        _ = action
    }

    func unregister(_ action: ShortcutAction) async {
        _ = action
    }
}

private extension UserDefaults {
    private enum Key {
        static let sourceLanguageID = "LinguistMac.settings.sourceLanguageID"
        static let targetLanguageID = "LinguistMac.settings.targetLanguageID"
        static let selectedProviderID = "LinguistMac.settings.selectedProviderID"
        static let autoCopyEnabled = "LinguistMac.settings.autoCopyEnabled"
        static let popupFontSize = "LinguistMac.settings.popupFontSize"
        static let popupWidth = "LinguistMac.settings.popupWidth"
        static let matchPopupWidthToSelection = "LinguistMac.settings.matchPopupWidthToSelection"
        static let hasCompletedOnboarding = "LinguistMac.hasCompletedOnboarding"
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
            .map(TranslationProviderID.init(rawValue:))
            ?? defaults.selectedProviderID

        return AppSettings(
            sourceLanguage: source,
            targetLanguage: target.canBeTargetLanguage ? target : defaults.targetLanguage,
            selectedProviderID: providerID,
            autoCopyEnabled: object(forKey: Key.autoCopyEnabled) as? Bool ?? defaults.autoCopyEnabled,
            launchAtLoginEnabled: defaults.launchAtLoginEnabled,
            screenTranslationShortcut: defaults.screenTranslationShortcut,
            textSelectionShortcut: defaults.textSelectionShortcut,
            quickTranslateShortcut: defaults.quickTranslateShortcut,
            popupFontSize: object(forKey: Key.popupFontSize) as? Double ?? defaults.popupFontSize,
            popupWidth: object(forKey: Key.popupWidth) as? Double ?? defaults.popupWidth,
            matchPopupWidthToSelection: object(forKey: Key.matchPopupWidthToSelection) as? Bool
                ?? defaults.matchPopupWidthToSelection,
            hasCompletedOnboarding: bool(forKey: Key.hasCompletedOnboarding)
        )
    }

    func saveLinguistSettings(_ settings: AppSettings) {
        set(settings.sourceLanguage.id, forKey: Key.sourceLanguageID)
        set(settings.targetLanguage.id, forKey: Key.targetLanguageID)
        set(settings.selectedProviderID.rawValue, forKey: Key.selectedProviderID)
        set(settings.autoCopyEnabled, forKey: Key.autoCopyEnabled)
        set(settings.popupFontSize, forKey: Key.popupFontSize)
        set(settings.popupWidth, forKey: Key.popupWidth)
        set(settings.matchPopupWidthToSelection, forKey: Key.matchPopupWidthToSelection)
        set(settings.hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
    }
}
