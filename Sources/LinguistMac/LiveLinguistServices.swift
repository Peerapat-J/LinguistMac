import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import LinguistMacCore

enum LiveLinguistServices {
    @MainActor
    static func make(shortcutRegistry: any ShortcutRegistering = NoOpShortcutRegistry()) -> LinguistServices {
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
            selectedTextCapture: SystemSelectedTextCaptureService(),
            shortcutRegistry: shortcutRegistry
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

@MainActor
final class SystemShortcutRegistry: ShortcutRegistering, @unchecked Sendable {
    var onAction: ((ShortcutAction) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeysByAction: [ShortcutAction: EventHotKeyRef] = [:]
    private var actionsByHotKeyID: [UInt32: ShortcutAction] = [:]

    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        try installEventHandlerIfNeeded()
        try unregisterHotKey(for: action)

        guard let keyCode = shortcut.carbonKeyCode else {
            throw SystemShortcutRegistryError.unsupportedKey(shortcut.key)
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.hotKeyID)
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw SystemShortcutRegistryError.registrationFailed(status)
        }

        hotKeysByAction[action] = hotKeyRef
        actionsByHotKeyID[action.hotKeyID] = action
    }

    func unregister(_ action: ShortcutAction) async {
        try? unregisterHotKey(for: action)
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard status == noErr, let handler else {
            throw SystemShortcutRegistryError.eventHandlerInstallFailed(status)
        }

        eventHandler = handler
    }

    private func unregisterHotKey(for action: ShortcutAction) throws {
        guard let hotKey = hotKeysByAction.removeValue(forKey: action) else {
            actionsByHotKeyID.removeValue(forKey: action.hotKeyID)
            return
        }

        let status = UnregisterEventHotKey(hotKey)
        guard status == noErr else {
            throw SystemShortcutRegistryError.unregistrationFailed(status)
        }

        actionsByHotKeyID.removeValue(forKey: action.hotKeyID)
    }

    private func dispatchHotKey(signature: OSType, id: UInt32) -> OSStatus {
        guard signature == Self.signature,
              let action = actionsByHotKeyID[id]
        else {
            return OSStatus(eventNotHandledErr)
        }

        onAction?(action)
        return noErr
    }

    private static let signature: OSType = 0x4C6E_674D

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return status
        }

        let pointerAddress = UInt(bitPattern: userData)
        let signature = hotKeyID.signature
        let id = hotKeyID.id

        return MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: pointerAddress) else {
                return OSStatus(eventNotHandledErr)
            }

            let registry = Unmanaged<SystemShortcutRegistry>
                .fromOpaque(pointer)
                .takeUnretainedValue()
            return registry.dispatchHotKey(signature: signature, id: id)
        }
    }
}

private enum SystemShortcutRegistryError: LocalizedError {
    case eventHandlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)
    case unregistrationFailed(OSStatus)
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallFailed(status):
            "Unable to install hot key handler (\(status))."
        case let .registrationFailed(status):
            "Unable to register hot key (\(status))."
        case let .unregistrationFailed(status):
            "Unable to unregister hot key (\(status))."
        case let .unsupportedKey(key):
            "Unsupported hot key: \(key)."
        }
    }
}

private extension ShortcutAction {
    var hotKeyID: UInt32 {
        switch self {
        case .screenTranslation:
            1
        case .textSelectionTranslation:
            2
        case .quickTranslate:
            3
        case .clipboardDoubleCopy:
            4
        case .dragTranslation:
            5
        }
    }
}

private extension KeyboardShortcut {
    var carbonKeyCode: UInt32? {
        switch key.uppercased() {
        case "A":
            UInt32(kVK_ANSI_A)
        case "B":
            UInt32(kVK_ANSI_B)
        case "C":
            UInt32(kVK_ANSI_C)
        case "D":
            UInt32(kVK_ANSI_D)
        case "E":
            UInt32(kVK_ANSI_E)
        case "F":
            UInt32(kVK_ANSI_F)
        case "G":
            UInt32(kVK_ANSI_G)
        case "H":
            UInt32(kVK_ANSI_H)
        case "I":
            UInt32(kVK_ANSI_I)
        case "J":
            UInt32(kVK_ANSI_J)
        case "K":
            UInt32(kVK_ANSI_K)
        case "L":
            UInt32(kVK_ANSI_L)
        case "M":
            UInt32(kVK_ANSI_M)
        case "N":
            UInt32(kVK_ANSI_N)
        case "O":
            UInt32(kVK_ANSI_O)
        case "P":
            UInt32(kVK_ANSI_P)
        case "Q":
            UInt32(kVK_ANSI_Q)
        case "R":
            UInt32(kVK_ANSI_R)
        case "S":
            UInt32(kVK_ANSI_S)
        case "T":
            UInt32(kVK_ANSI_T)
        case "U":
            UInt32(kVK_ANSI_U)
        case "V":
            UInt32(kVK_ANSI_V)
        case "W":
            UInt32(kVK_ANSI_W)
        case "X":
            UInt32(kVK_ANSI_X)
        case "Y":
            UInt32(kVK_ANSI_Y)
        case "Z":
            UInt32(kVK_ANSI_Z)
        case "0":
            UInt32(kVK_ANSI_0)
        case "1":
            UInt32(kVK_ANSI_1)
        case "2":
            UInt32(kVK_ANSI_2)
        case "3":
            UInt32(kVK_ANSI_3)
        case "4":
            UInt32(kVK_ANSI_4)
        case "5":
            UInt32(kVK_ANSI_5)
        case "6":
            UInt32(kVK_ANSI_6)
        case "7":
            UInt32(kVK_ANSI_7)
        case "8":
            UInt32(kVK_ANSI_8)
        case "9":
            UInt32(kVK_ANSI_9)
        default:
            nil
        }
    }

    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if self.modifiers.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if self.modifiers.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if self.modifiers.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if self.modifiers.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }
}

private extension UserDefaults {
    private enum Key {
        static let sourceLanguageID = "LinguistMac.settings.sourceLanguageID"
        static let targetLanguageID = "LinguistMac.settings.targetLanguageID"
        static let selectedProviderID = "LinguistMac.settings.selectedProviderID"
        static let autoCopyEnabled = "LinguistMac.settings.autoCopyEnabled"
        static let doubleCopyTranslationEnabled = "LinguistMac.settings.doubleCopyTranslationEnabled"
        static let dragTranslationEnabled = "LinguistMac.settings.dragTranslationEnabled"
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
            doubleCopyTranslationEnabled: object(forKey: Key.doubleCopyTranslationEnabled) as? Bool
                ?? defaults.doubleCopyTranslationEnabled,
            dragTranslationEnabled: object(forKey: Key.dragTranslationEnabled) as? Bool
                ?? defaults.dragTranslationEnabled,
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
        set(settings.doubleCopyTranslationEnabled, forKey: Key.doubleCopyTranslationEnabled)
        set(settings.dragTranslationEnabled, forKey: Key.dragTranslationEnabled)
        set(settings.popupFontSize, forKey: Key.popupFontSize)
        set(settings.popupWidth, forKey: Key.popupWidth)
        set(settings.matchPopupWidthToSelection, forKey: Key.matchPopupWidthToSelection)
        set(settings.hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
    }
}
