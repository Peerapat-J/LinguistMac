import AppKit
import Combine
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
    @Published var screenSessionState: TranslationSessionState
    @Published var inputModeSessionState: TranslationSessionState
    @Published private(set) var shortcutRegistrationResults: [ShortcutRegistrationResult]
    @Published var readiness: OnboardingReadinessSnapshot
    @Published var availableProviders: [TranslationProviderDescriptor]
    @Published var providerAPIKeyDrafts: [TranslationProviderID: String]
    @Published var providerAPIRegionDrafts: [TranslationProviderID: String]
    @Published var providerConfigurationMessages: [TranslationProviderID: String]
    @Published var appPreferenceMessage: String?
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
        screenSessionState = .idle
        inputModeSessionState = .idle
        shortcutRegistrationResults = []
        readiness = OnboardingReadinessSnapshot.make(
            screenRecording: .notDetermined,
            accessibility: .notDetermined,
            appleTranslation: .unknown,
            cloudProviderConfigured: false
        )
        providerAPIKeyDrafts = [:]
        providerAPIRegionDrafts = [:]
        providerConfigurationMessages = [:]
        appPreferenceMessage = nil
        historyLoadError = nil
        self.services = services
        shortcutRegistrationCoordinator = ShortcutRegistrationCoordinator(registry: services.shortcutRegistry)
        doubleCopyTriggerDetector = DoubleCopyTriggerDetector()
        if initialSettings != storedSettings {
            persistSettings()
        }
    }

    deinit {
        activePopupWordLookupTask?.cancel()
        activeQuickWordTranslationTask?.cancel()
    }

    var recentMenuItems: [TranslationResult] {
        Array(recentTranslations.prefix(5))
    }

    func record(_ command: AppShellCommand) {
        lastCommand = command
    }

    func prepareQuickTranslate() {
        record(.quickTranslate)
        cancelQuickWordTranslation()
        quickDraft.sourceLanguage = settings.sourceLanguage
        quickDraft.targetLanguage = settings.targetLanguage
        quickSessionState = .idle
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
            appleTranslation: appleTranslation,
            cloudProviderConfigured: cloudProviderConfigured
        )
    }

    func refreshShortcutRegistrations() async {
        let accessibility = await services.permissionChecker.status(for: .accessibility)
        shortcutRegistrationResults = await shortcutRegistrationCoordinator.refresh(
            settings: settings,
            accessibilityStatus: accessibility
        )
    }

    func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func persistSettings() {
        let settings = settings
        let store = services.settingsStore
        Task {
            try? await store.saveSettings(settings)
        }
    }
}
