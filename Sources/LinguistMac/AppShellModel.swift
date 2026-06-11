import AppKit
import Combine
import LinguistMacCore

enum AppWindow: String {
    case status
    case quickTranslate
    case translationPopup
    case onboarding
}

enum AppShellCommand: Equatable {
    case screenTranslate
    case quickTranslate
    case settings
    case history
    case onboarding
    case about
    case quit
    case copyTranslation
    case openSystemSettings(PermissionKind)
}

@MainActor
final class AppShellModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
        }
    }

    @Published private(set) var recentTranslations: [TranslationResult]
    @Published var popupState: TranslationPopupState
    @Published var quickDraft: QuickTranslateDraft
    @Published var quickSessionState: TranslationSessionState
    @Published var screenSessionState: TranslationSessionState
    @Published var inputModeSessionState: TranslationSessionState
    @Published private(set) var shortcutRegistrationResults: [ShortcutRegistrationResult]
    @Published var readiness: OnboardingReadinessSnapshot
    @Published private(set) var lastCommand: AppShellCommand?

    let availableLanguages = TranslationLanguageCatalog.defaultLanguages
    let availableProviders: [TranslationProviderDescriptor]

    private let services: LinguistServices
    private let shortcutRegistrationCoordinator: ShortcutRegistrationCoordinator
    private var doubleCopyTriggerDetector: DoubleCopyTriggerDetector

    private static let liveAvailableProviders: [TranslationProviderDescriptor] = [
        TranslationProviderDescriptor(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false
        )
    ]

    init(
        settings: AppSettings? = nil,
        recentTranslations: [TranslationResult] = [],
        services: LinguistServices = LiveLinguistServices.make()
    ) {
        let storedSettings = settings ?? UserDefaultsAppSettingsStore.loadInitialSettings()
        let initialSettings = storedSettings.selectingAvailableProvider(from: Self.liveAvailableProviders)

        availableProviders = Self.liveAvailableProviders
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
        self.services = services
        shortcutRegistrationCoordinator = ShortcutRegistrationCoordinator(registry: services.shortcutRegistry)
        doubleCopyTriggerDetector = DoubleCopyTriggerDetector()
        if initialSettings != storedSettings {
            persistSettings()
        }
    }

    var recentMenuItems: [TranslationResult] {
        Array(recentTranslations.prefix(5))
    }

    func record(_ command: AppShellCommand) {
        lastCommand = command
    }

    func prepareQuickTranslate() {
        record(.quickTranslate)
        quickDraft.sourceLanguage = settings.sourceLanguage
        quickDraft.targetLanguage = settings.targetLanguage
        quickSessionState = .idle
    }

    func runScreenTranslation() async {
        record(.screenTranslate)

        let loadingRequest = TranslationRequest(
            text: "",
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage,
            inputMode: .screenSelection,
            providerID: settings.selectedProviderID
        )
        screenSessionState = .capturing

        let coordinator = ScreenTranslationCoordinator(services: services)
        let finalState = await coordinator.translateScreenSelection(settings: settings)
        screenSessionState = finalState

        switch finalState {
        case let .completed(result):
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)
        case let .failed(failure):
            popupState = .failed(failure, originalText: nil)
        case let .translating(request):
            popupState = .loading(request)
        case .idle, .requestingPermission, .capturing, .recognizing:
            popupState = .loading(loadingRequest)
        }
    }

    func runQuickTranslate() async {
        do {
            let request = try quickDraft
                .makeRequest(providerID: settings.selectedProviderID)
                .resolvingAutoDetectedSource()
            quickSessionState = .translating(request)
            popupState = .loading(request)

            let readiness = await services.languageAvailability.readiness(
                from: request.sourceLanguage,
                to: request.targetLanguage,
                sampleText: request.text
            )
            switch readiness {
            case .ready, .unknown:
                break
            case .needsDownload:
                throw TranslationFailure.missingLanguagePack(request.providerID)
            case .unavailable:
                throw TranslationFailure.unsupportedLanguagePair
            }

            let translator = try await services.translatorRegistry.provider(for: request.providerID)
            let result = try await translator.translate(request)
            quickSessionState = .completed(result)
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)
            try? await services.historyStore.save(result)

            if settings.autoCopyEnabled {
                await services.clipboard.writeText(result.translatedText)
            }
        } catch let failure as TranslationFailure {
            quickSessionState = .failed(failure)
            popupState = .failed(failure, originalText: quickDraft.trimmedText)
        } catch {
            let failure = TranslationFailure.providerFailed(error.localizedDescription)
            quickSessionState = .failed(failure)
            popupState = .failed(failure, originalText: quickDraft.trimmedText)
        }
    }

    func runSelectedTextTranslation() async {
        await runInputModeTranslation(.selectedText) { coordinator, settings in
            await coordinator.translateSelectedText(settings: settings)
        }
    }

    func runClipboardDoubleCopyTranslation() async {
        await runInputModeTranslation(.clipboardDoubleCopy) { coordinator, settings in
            await coordinator.translateClipboardDoubleCopy(settings: settings)
        }
    }

    func runDragTranslation() async {
        await runInputModeTranslation(.dragTranslation) { coordinator, settings in
            await coordinator.translateDragSelection(settings: settings)
        }
    }

    @discardableResult
    func observeCopyCommand(at date: Date = Date()) async -> Bool {
        guard settings.doubleCopyTranslationEnabled,
              doubleCopyTriggerDetector.recordCopyCommand(at: date)
        else {
            return false
        }

        await runClipboardDoubleCopyTranslation()
        return true
    }

    func togglePopupOriginal() {
        popupState = popupState.toggledOriginalVisibility()
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

    func copyPopupText() async {
        guard let text = popupState.copyableText else {
            return
        }

        record(.copyTranslation)
        await services.clipboard.writeText(text)
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

        readiness = OnboardingReadinessSnapshot.make(
            screenRecording: screenRecording,
            accessibility: accessibility,
            appleTranslation: appleTranslation,
            cloudProviderConfigured: false
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

    func openSystemSettings(for kind: PermissionKind) {
        record(.openSystemSettings(kind))

        guard let url = systemSettingsURL(for: kind) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func saveRecent(_ result: TranslationResult) {
        recentTranslations.insert(result, at: 0)
        recentTranslations = Array(recentTranslations.prefix(10))
    }

    private func persistSettings() {
        let settings = settings
        let store = services.settingsStore
        Task {
            try? await store.saveSettings(settings)
        }
    }

    private func runInputModeTranslation(
        _ inputMode: TranslationInputMode,
        operation: (InputModeTranslationCoordinator, AppSettings) async -> TranslationSessionState
    ) async {
        let loadingRequest = TranslationRequest(
            text: "",
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage,
            inputMode: inputMode,
            providerID: settings.selectedProviderID
        )
        inputModeSessionState = .capturing
        popupState = .loading(loadingRequest)

        let coordinator = InputModeTranslationCoordinator(services: services)
        let finalState = await operation(coordinator, settings)
        inputModeSessionState = finalState

        switch finalState {
        case let .completed(result):
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)
        case let .failed(failure):
            popupState = .failed(failure, originalText: nil)
        case let .translating(request):
            popupState = .loading(request)
        case .idle, .requestingPermission, .capturing, .recognizing:
            popupState = .loading(loadingRequest)
        }
    }

    private func systemSettingsURL(for kind: PermissionKind) -> URL? {
        switch kind {
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .keychain, .network:
            URL(string: "x-apple.systempreferences:com.apple.preference.security")
        }
    }
}

actor SystemClipboardService: ClipboardServicing {
    func readText() async -> String? {
        await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
    }

    func writeText(_ text: String) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
