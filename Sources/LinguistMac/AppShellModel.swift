import Combine
import Foundation
import LinguistMacCore

enum AppWindow: String {
    case status, quickTranslate, translationPopup, onboarding
}

enum AppShellCommand: Equatable {
    case screenTranslate
    case quickTranslate
    case selectedTextTranslate
    case clipboardDoubleCopyTranslate
    case dragTranslate
    case settings
    case history
    case onboarding
    case about
    case quit
    case copyTranslation
    case openSystemSettings(PermissionKind)
}

struct HistoryLoadErrorState: Equatable {
    let message: String
    let diagnosticDescription: String
}

@MainActor
final class AppShellModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
        }
    }

    @Published var recentTranslations: [TranslationResult]
    @Published var popupState: TranslationPopupState
    @Published var quickDraft: QuickTranslateDraft
    @Published var quickSessionState: TranslationSessionState
    @Published var quickVoiceState: SpeechRecognitionSessionState
    @Published var quickVoiceTranscript: String?
    @Published var spokenOutputState: SpokenOutputSessionState
    @Published var screenSessionState: TranslationSessionState
    @Published var inputModeSessionState: TranslationSessionState
    @Published private(set) var shortcutRegistrationResults: [ShortcutRegistrationResult]
    @Published var readiness: OnboardingReadinessSnapshot
    @Published var appleLanguagePackSelection: AppleLanguagePackSelection
    @Published var appleLanguagePackGroups: [AppleLanguagePackGroup]
    @Published var availableProviders: [TranslationProviderDescriptor]
    @Published var providerAPIKeyDrafts: [TranslationProviderID: String]
    @Published var providerAPIRegionDrafts: [TranslationProviderID: String]
    @Published var providerConfigurationMessages: [TranslationProviderID: String]
    @Published var appPreferenceMessage: String?
    @Published var screenTranslationSoundNames: [String]
    @Published var screenTranslationNotificationMessage: String?
    @Published var historyLoadError: HistoryLoadErrorState?
    @Published private(set) var lastCommand: AppShellCommand?

    let availableLanguages = TranslationLanguageCatalog.defaultLanguages

    let services: LinguistServices
    let shortcutRegistrationCoordinator: ShortcutRegistrationCoordinator
    var doubleCopyTriggerDetector: DoubleCopyTriggerDetector
    var activePopupWordLookupID: UUID?
    var activePopupWordLookupTask: Task<WordLookupState, Never>?
    var activeQuickWordTranslationID: UUID?
    var activeQuickWordTranslationTask: Task<Void, Never>?
    var activeQuickVoiceCaptureID: UUID?
    var activeQuickVoiceCaptureTask: Task<Void, Never>?
    var activeSpokenOutputID: UUID?
    var activeSpokenOutputResultID: UUID?
    var activeSpokenOutputTask: Task<Void, Never>?
    var preparingAppleLanguagePackID: String?
    var appleLanguagePackMessages: [String: String]

    init(
        settings: AppSettings? = nil,
        recentTranslations: [TranslationResult] = [],
        services: LinguistServices = LiveLinguistServices.make()
    ) {
        let storedSettings = settings ?? UserDefaultsAppSettingsStore.loadInitialSettings()
        let initialProviders = TranslationProviderCatalog.defaultDescriptors()
        let initialSettings = storedSettings
            .selectingAvailableProvider(from: initialProviders)
            .sanitized()

        availableProviders = initialProviders
        self.settings = initialSettings
        self.recentTranslations = recentTranslations
        popupState = .empty
        quickDraft = QuickTranslateDraft(
            sourceLanguage: initialSettings.sourceLanguage,
            targetLanguage: initialSettings.targetLanguage
        )
        quickSessionState = .idle
        quickVoiceState = .idle
        quickVoiceTranscript = nil
        spokenOutputState = .idle
        screenSessionState = .idle
        inputModeSessionState = .idle
        shortcutRegistrationResults = []
        readiness = OnboardingReadinessSnapshot.make(
            screenRecording: .notDetermined,
            accessibility: .notDetermined,
            microphone: .notDetermined,
            speechRecognition: .notDetermined,
            appleTranslation: .unknown,
            cloudProviderConfigured: false
        )
        appleLanguagePackSelection = AppleLanguagePackSelection.initial(settings: initialSettings)
        appleLanguagePackGroups = AppleLanguagePackCatalog.groups(
            from: TranslationLanguageCatalog.defaultLanguages,
            settings: initialSettings
        )
        providerAPIKeyDrafts = [:]
        providerAPIRegionDrafts = [:]
        providerConfigurationMessages = [:]
        appPreferenceMessage = nil
        screenTranslationSoundNames = []
        screenTranslationNotificationMessage = nil
        historyLoadError = nil
        self.services = services
        shortcutRegistrationCoordinator = ShortcutRegistrationCoordinator(registry: services.shortcutRegistry)
        doubleCopyTriggerDetector = DoubleCopyTriggerDetector()
        preparingAppleLanguagePackID = nil
        appleLanguagePackMessages = [:]
        if initialSettings != storedSettings {
            persistSettings()
        }
    }

    deinit {
        activePopupWordLookupTask?.cancel()
        activeQuickWordTranslationTask?.cancel()
        activeQuickVoiceCaptureTask?.cancel()
        activeSpokenOutputTask?.cancel()
    }

    var recentMenuItems: [TranslationResult] {
        Array(recentTranslations.prefix(5))
    }

    func record(_ command: AppShellCommand) {
        lastCommand = command
    }

    func prepareQuickTranslate() {
        record(.quickTranslate)
        stopSpokenOutput()
        cancelQuickWordTranslation()
        clearActiveQuickVoiceCapture()
        quickDraft.sourceLanguage = settings.sourceLanguage
        quickDraft.targetLanguage = settings.targetLanguage
        quickSessionState = .idle
        quickVoiceState = .idle
        quickVoiceTranscript = nil
    }

    func swapQuickDraftLanguages() {
        var selection = LanguageSelection(
            source: quickDraft.sourceLanguage,
            target: quickDraft.targetLanguage
        )
        selection.swap()
        quickDraft.sourceLanguage = selection.source
        quickDraft.targetLanguage = selection.target
    }

    func markOnboardingComplete() {
        setOnboardingCompleted(true)
    }

    func setOnboardingCompleted(_ isCompleted: Bool) {
        settings.hasCompletedOnboarding = isCompleted
    }

    func reopenOnboarding() {
        record(.onboarding)
    }

    func refreshReadiness() async {
        let screenRecording = await services.permissionChecker.status(for: .screenRecording)
        let accessibility = await services.permissionChecker.status(for: .accessibility)
        let microphone = await services.permissionChecker.status(for: .microphone)
        let speechRecognition = await services.permissionChecker.status(for: .speechRecognition)
        let appleTranslation = await services.languageAvailability.readiness(
            from: settings.sourceLanguage,
            to: settings.targetLanguage,
            sampleText: nil
        )
        let cloudProviderConfigured = availableProviders.contains {
            $0.usesNetwork && $0.isConfigured
        }

        readiness = OnboardingReadinessSnapshot.make(
            screenRecording: screenRecording,
            accessibility: accessibility,
            microphone: microphone,
            speechRecognition: speechRecognition,
            appleTranslation: appleTranslation,
            cloudProviderConfigured: cloudProviderConfigured
        )
    }

    func handleVoicePermissionSetupAction(
        for kind: PermissionKind,
        currentStatus: PermissionStatus
    ) async {
        guard kind == .microphone || kind == .speechRecognition else {
            openSystemSettings(for: kind)
            return
        }

        guard currentStatus == .notDetermined else {
            openSystemSettings(for: kind)
            return
        }

        _ = await services.permissionChecker.request(for: kind)
        await refreshReadiness()
    }

    func refreshShortcutRegistrations() async {
        let accessibility = await services.permissionChecker.status(for: .accessibility)
        shortcutRegistrationResults = await shortcutRegistrationCoordinator.refresh(
            settings: settings,
            accessibilityStatus: accessibility
        )
    }

    func refreshScreenTranslationSoundNames() async {
        let soundNames = await services.screenTranslationSoundPlayer.availableSoundNames()
        screenTranslationSoundNames = soundNames
        let resolvedSoundName = ScreenTranslationSoundPolicy.resolvedSoundName(
            settings.screenTranslationSoundName,
            from: soundNames
        )
        if settings.screenTranslationSoundName != resolvedSoundName {
            settings.screenTranslationSoundName = resolvedSoundName
        }
    }

    func playSelectedScreenTranslationSound() async {
        await services.screenTranslationSoundPlayer.playSound(named: settings.screenTranslationSoundName)
    }

    func setScreenTranslationNotificationsEnabled(_ isEnabled: Bool) async {
        guard isEnabled else {
            settings.screenTranslationNotificationsEnabled = false
            screenTranslationNotificationMessage = nil
            return
        }

        let status = await services.screenTranslationNotifier.requestAuthorization()
        switch status {
        case .authorized:
            settings.screenTranslationNotificationsEnabled = true
            screenTranslationNotificationMessage = nil
        case .denied:
            settings.screenTranslationNotificationsEnabled = false
            screenTranslationNotificationMessage = "Notifications are disabled in macOS Settings."
        case .notDetermined:
            settings.screenTranslationNotificationsEnabled = false
            screenTranslationNotificationMessage = "Notification permission is still waiting for a system response."
        case .unavailable:
            settings.screenTranslationNotificationsEnabled = false
            screenTranslationNotificationMessage = "Notifications are unavailable on this Mac."
        }
    }

    func openScreenTranslationNotificationSettings() async {
        await services.screenTranslationNotifier.openNotificationSettings()
    }

    func speakTranslation(_ result: TranslationResult) {
        stopSpokenOutput()
        let outputID = UUID()
        let request = SpokenOutputRequest(result: result)
        activeSpokenOutputID = outputID
        activeSpokenOutputResultID = result.id
        spokenOutputState = .preparing(request.normalized)
        activeSpokenOutputTask = Task {
            await runSpokenOutput(request, outputID: outputID)
        }
    }

    func stopSpokenOutput() {
        activeSpokenOutputID = nil
        activeSpokenOutputResultID = nil
        activeSpokenOutputTask?.cancel()
        activeSpokenOutputTask = nil
        spokenOutputState = .idle
    }

    func isSpokenOutputActive(for result: TranslationResult) -> Bool {
        guard activeSpokenOutputResultID == result.id else {
            return false
        }

        switch spokenOutputState {
        case .preparing, .speaking:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private func persistSettings() {
        let settings = settings
        let store = services.settingsStore
        Task {
            try? await store.saveSettings(settings)
        }
    }

    private func runSpokenOutput(
        _ request: SpokenOutputRequest,
        outputID: UUID
    ) async {
        let coordinator = SpokenOutputCoordinator(services: services)
        let finalState = await coordinator.speak(request, sessionID: outputID) { [weak self] state in
            await self?.applySpokenOutputState(state, outputID: outputID)
        }
        finishSpokenOutput(finalState, outputID: outputID)
    }

    private func applySpokenOutputState(
        _ state: SpokenOutputSessionState,
        outputID: UUID
    ) {
        guard activeSpokenOutputID == outputID else {
            return
        }

        spokenOutputState = state
    }

    private func finishSpokenOutput(
        _ finalState: SpokenOutputSessionState,
        outputID: UUID
    ) {
        guard activeSpokenOutputID == outputID else {
            return
        }

        spokenOutputState = finalState
        activeSpokenOutputID = nil
        activeSpokenOutputTask = nil
    }
}
