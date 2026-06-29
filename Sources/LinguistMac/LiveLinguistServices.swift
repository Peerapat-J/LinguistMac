import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import KeyboardShortcuts
import LinguistMacCore
import Speech
import UserNotifications

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
            spokenOutput: AppleSpokenOutputService(),
            screenTranslationSoundPlayer: SystemScreenTranslationSoundPlayer(),
            screenTranslationNotifier: SystemScreenTranslationNotifier()
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

    private var tasksByAction: [ShortcutAction: Task<Void, Never>] = [:]

    deinit {
        tasksByAction.values.forEach { $0.cancel() }
    }

    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        guard let keyboardShortcut = shortcut.keyboardShortcutsShortcut else {
            throw SystemShortcutRegistryError.unsupportedKey(shortcut.key)
        }

        tasksByAction[action]?.cancel()
        tasksByAction[action] = Task { [weak self] in
            for await _ in KeyboardShortcuts.events(.keyUp, for: keyboardShortcut) {
                await MainActor.run {
                    self?.onAction?(action)
                }
            }
        }
    }

    func unregister(_ action: ShortcutAction) async {
        tasksByAction[action]?.cancel()
        tasksByAction[action] = nil
    }
}

private enum SystemShortcutRegistryError: LocalizedError {
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedKey(key):
            "Unsupported hot key: \(key)."
        }
    }
}

struct SystemScreenTranslationSoundPlayer: ScreenTranslationSoundPlaying {
    private let soundsDirectory: URL

    init(
        soundsDirectory: URL = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    ) {
        self.soundsDirectory = soundsDirectory
    }

    func availableSoundNames() async -> [String] {
        let soundExtensions = Set(["aiff", "aif", "wav", "mp3", "m4a"])
        let soundURLs = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return soundURLs
            .filter { soundExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func playSound(named soundName: String) async {
        let soundNames = await availableSoundNames()
        let resolvedSoundName = ScreenTranslationSoundPolicy.resolvedSoundName(soundName, from: soundNames)

        await MainActor.run {
            _ = NSSound(named: NSSound.Name(resolvedSoundName))?.play()
        }
    }
}

final class SystemScreenTranslationNotifier: NSObject, ScreenTranslationNotificationPosting, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter
    private let notificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.notifications"
    )

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.delegate = self
    }

    func authorizationStatus() async -> ScreenTranslationNotificationStatus {
        let settings = await notificationCenter.notificationSettings()
        return Self.authorizationStatus(from: settings.authorizationStatus)
    }

    func requestAuthorization() async -> ScreenTranslationNotificationStatus {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert])
            return await authorizationStatus()
        } catch {
            return .unavailable
        }
    }

    func postScreenTranslation(result: TranslationResult) async {
        guard await authorizationStatus().allowsPosting else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Screen Translate"
        content.body = Self.notificationBody(for: result)

        let request = UNNotificationRequest(
            identifier: "screen-translation-\(result.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    func openNotificationSettings() async {
        guard let notificationSettingsURL else {
            return
        }

        await MainActor.run {
            _ = NSWorkspace.shared.open(notificationSettingsURL)
        }
    }

    private static func authorizationStatus(
        from status: UNAuthorizationStatus
    ) -> ScreenTranslationNotificationStatus {
        switch status {
        case .authorized, .provisional:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .ephemeral:
            .authorized
        @unknown default:
            .unavailable
        }
    }

    private static func notificationBody(for result: TranslationResult) -> String {
        "Original: \(result.originalText)\nTranslation: \(result.translatedText)"
    }
}

extension SystemScreenTranslationNotifier: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        _ = center
        _ = notification
        return [.banner, .list]
    }
}

private typealias SpeechSynthesizerDelegate = AVSpeechSynthesizerDelegate

enum AppleSpokenOutputVoiceSelector {
    static func preferredLanguageID(
        for requestedLanguageID: String,
        availableLanguageIDs: [String]
    ) -> String? {
        if let exactLanguageID = availableLanguageIDs.first(where: { $0 == requestedLanguageID }) {
            return exactLanguageID
        }

        guard let requestedLanguageCode = languageCode(for: requestedLanguageID) else {
            return nil
        }

        return availableLanguageIDs.first { languageID in
            languageCode(for: languageID) == requestedLanguageCode
        }
    }

    private static func languageCode(for identifier: String) -> String? {
        Locale(identifier: identifier).language.languageCode?.identifier
            ?? identifier.split(separator: "-").first.map(String.init)
            ?? identifier.split(separator: "_").first.map(String.init)
    }
}

@MainActor
final class AppleSpokenOutputService: NSObject, SpokenOutputServicing, SpeechSynthesizerDelegate {
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
                    result: .failure(SpokenOutputFailure.cancelled),
                    stopSynthesizer: true
                )
            }
        }
    }

    func stop(sessionID: UUID) async {
        finishActiveSpeech(
            sessionID: sessionID,
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
        sessionID: UUID,
        result: Result<Void, Error>,
        stopSynthesizer: Bool
    ) {
        guard activeSessionID == sessionID else {
            return
        }

        finishActiveSpeech(result: result, stopSynthesizer: stopSynthesizer)
    }

    private func finishActiveSpeech(
        synthesizerID: ObjectIdentifier,
        result: Result<Void, Error>,
        stopSynthesizer: Bool
    ) {
        guard activeSynthesizer.map(ObjectIdentifier.init) == synthesizerID else {
            return
        }

        finishActiveSpeech(result: result, stopSynthesizer: stopSynthesizer)
    }

    private func finishActiveSpeech(
        result: Result<Void, Error>,
        stopSynthesizer: Bool
    ) {
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
        guard !language.supportsAutoDetect else {
            return nil
        }

        let voices = AVSpeechSynthesisVoice.speechVoices()
        let voiceLanguageIDs = voices.map(\.language)
        guard let selectedLanguageID = AppleSpokenOutputVoiceSelector.preferredLanguageID(
            for: language.id,
            availableLanguageIDs: voiceLanguageIDs
        ) else {
            return nil
        }

        return voices.first { voice in
            voice.language == selectedLanguageID
        }
    }
}
