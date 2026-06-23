import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import CoreGraphics
import Foundation
import LinguistMacCore
import Speech

enum LiveLinguistServices {
    @MainActor
    static func make(
        shortcutRegistry: any ShortcutRegistering = NoOpShortcutRegistry(),
        historyStoreFactory: () throws -> any TranslationHistoryStoring = {
            try SwiftDataTranslationHistoryStore.make()
        }
    ) -> LinguistServices {
        let settingsStore = UserDefaultsAppSettingsStore()
        let apiKeyStore = KeychainAPIKeyStore()
        let cloudClient = URLSessionCloudTranslationClient()
        let historyStore = makeHistoryStore(factory: historyStoreFactory)
        let translatorRegistry = DefaultTranslationProviderRegistry(
            providers: [
                AppleTranslationProvider(),
                CloudTranslationProvider(id: .deepl, apiKeyStore: apiKeyStore, client: cloudClient),
                CloudTranslationProvider(id: .googleCloud, apiKeyStore: apiKeyStore, client: cloudClient),
                CloudTranslationProvider(id: .microsoftAzure, apiKeyStore: apiKeyStore, client: cloudClient)
            ]
        )

        return LinguistServices(
            screenCapture: ScreenCaptureKitScreenCaptureService(),
            ocr: AppleVisionOCRService(),
            translatorRegistry: translatorRegistry,
            languageAvailability: AppleTranslationAvailabilityService(),
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            launchAtLogin: SystemLaunchAtLoginService(),
            historyStore: historyStore,
            permissionChecker: SystemPermissionChecker(),
            clipboard: SystemClipboardService(),
            selectedTextCapture: SystemSelectedTextCaptureService(),
            shortcutRegistry: shortcutRegistry,
            wordLookupProvider: ProviderBackedWordLookupService(translatorRegistry: translatorRegistry),
            speechToText: AppleSpeechToTextService(),
            spokenOutput: AppleSpokenOutputService()
        )
    }

    private static func makeHistoryStore(
        factory: () throws -> any TranslationHistoryStoring
    ) -> any TranslationHistoryStoring {
        do {
            return try factory()
        } catch {
            return UnavailableTranslationHistoryStore(initializationError: error)
        }
    }
}

struct TranslationHistoryStoreUnavailableError: LocalizedError {
    let reason: String

    init(initializationError: Error) {
        reason = initializationError.localizedDescription
    }

    var errorDescription: String? {
        "Translation history storage is unavailable. \(reason)"
    }
}

struct UnavailableTranslationHistoryStore: TranslationHistoryStoring {
    private let error: TranslationHistoryStoreUnavailableError

    init(initializationError: Error) {
        error = TranslationHistoryStoreUnavailableError(initializationError: initializationError)
    }

    func save(_ result: TranslationResult) async throws {
        _ = result
        throw error
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        _ = limit
        throw error
    }
}

struct SystemPermissionChecker: PermissionChecking {
    func status(for kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .notDetermined
        case .microphone:
            Self.permissionStatus(from: AVCaptureDevice.authorizationStatus(for: .audio))
        case .speechRecognition:
            Self.permissionStatus(from: SFSpeechRecognizer.authorizationStatus())
        case .keychain:
            .granted
        case .network:
            .notDetermined
        }
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .screenRecording:
            CGRequestScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            await requestAccessibilityPermission()
        case .microphone:
            await requestMicrophonePermission()
        case .speechRecognition:
            await requestSpeechRecognitionPermission()
        case .keychain:
            .granted
        case .network:
            .notDetermined
        }
    }

    private func requestAccessibilityPermission() async -> PermissionStatus {
        await MainActor.run {
            let options = [
                Self.accessibilityPromptOptionKey: true
            ] as CFDictionary

            guard !AXIsProcessTrustedWithOptions(options) else {
                return .granted
            }

            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return AXIsProcessTrusted() ? .granted : .notDetermined
        }
    }

    private func requestMicrophonePermission() async -> PermissionStatus {
        let isGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }

        return isGranted ? .granted : Self.permissionStatus(from: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    private func requestSpeechRecognitionPermission() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.permissionStatus(from: status))
            }
        }
    }

    private static func permissionStatus(from status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }

    private static func permissionStatus(
        from status: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionStatus {
        switch status {
        case .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }

    private static let accessibilityPromptOptionKey = "AXTrustedCheckOptionPrompt"
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

private typealias SpeechSynthesizerDelegate = AVSpeechSynthesizerDelegate

@MainActor
final class AppleSpokenOutputService: NSObject, SpokenOutputServicing, SpeechSynthesizerDelegate, @unchecked Sendable {
    private var activeSynthesizer: AVSpeechSynthesizer?
    private var activeContinuation: CheckedContinuation<Void, Error>?
    private var activeSessionID: UUID?

    func canSpeak(language: TranslationLanguage) async -> Bool {
        Self.voice(for: language) != nil
    }

    func speak(_ request: SpokenOutputRequest, sessionID: UUID) async throws {
        try Task.checkCancellation()
        let normalizedRequest = request.normalized
        guard !normalizedRequest.trimmedText.isEmpty else {
            throw SpokenOutputFailure.emptyText
        }
        guard let voice = Self.voice(for: normalizedRequest.language) else {
            throw SpokenOutputFailure.unsupportedLanguage(normalizedRequest.language)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startSpeaking(
                    normalizedRequest,
                    voice: voice,
                    sessionID: sessionID,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { @MainActor in
                self.finishActiveSpeech(
                    sessionID: sessionID,
                    synthesizerID: nil,
                    result: .failure(SpokenOutputFailure.cancelled),
                    stopSynthesizer: true
                )
            }
        }
    }

    func stop(sessionID: UUID) async {
        finishActiveSpeech(
            sessionID: sessionID,
            synthesizerID: nil,
            result: .failure(SpokenOutputFailure.cancelled),
            stopSynthesizer: true
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        _ = utterance
        let synthesizerID = ObjectIdentifier(synthesizer)
        Task { @MainActor in
            self.finishActiveSpeech(
                sessionID: nil,
                synthesizerID: synthesizerID,
                result: .success(()),
                stopSynthesizer: false
            )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        _ = utterance
        let synthesizerID = ObjectIdentifier(synthesizer)
        Task { @MainActor in
            self.finishActiveSpeech(
                sessionID: nil,
                synthesizerID: synthesizerID,
                result: .failure(SpokenOutputFailure.cancelled),
                stopSynthesizer: false
            )
        }
    }

    private func startSpeaking(
        _ request: SpokenOutputRequest,
        voice: AVSpeechSynthesisVoice,
        sessionID: UUID,
        continuation: CheckedContinuation<Void, Error>
    ) {
        finishActiveSpeech(
            sessionID: nil,
            synthesizerID: nil,
            result: .failure(SpokenOutputFailure.cancelled),
            stopSynthesizer: true
        )

        activeSessionID = sessionID
        activeContinuation = continuation

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        activeSynthesizer = synthesizer

        let utterance = AVSpeechUtterance(string: request.trimmedText)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    private func finishActiveSpeech(
        sessionID: UUID?,
        synthesizerID expectedSynthesizerID: ObjectIdentifier?,
        result: Result<Void, Error>,
        stopSynthesizer: Bool
    ) {
        guard sessionID == nil || activeSessionID == sessionID else {
            return
        }
        guard expectedSynthesizerID == nil
            || activeSynthesizer.map(ObjectIdentifier.init) == expectedSynthesizerID
        else {
            return
        }

        let synthesizer = activeSynthesizer
        let continuation = activeContinuation

        activeSynthesizer = nil
        activeContinuation = nil
        activeSessionID = nil

        synthesizer?.delegate = nil
        if stopSynthesizer {
            synthesizer?.stopSpeaking(at: .immediate)
        }

        continuation?.resume(with: result)
    }

    private static func voice(for language: TranslationLanguage) -> AVSpeechSynthesisVoice? {
        guard !language.supportsAutoDetect,
              let requestedLanguageCode = languageCode(for: language.id)
        else {
            return nil
        }

        return AVSpeechSynthesisVoice.speechVoices().first { voice in
            voice.language == language.id
                || languageCode(for: voice.language) == requestedLanguageCode
        }
    }

    private static func languageCode(for identifier: String) -> String? {
        Locale(identifier: identifier).language.languageCode?.identifier
            ?? identifier.split(separator: "-").first.map(String.init)
            ?? identifier.split(separator: "_").first.map(String.init)
    }
}
