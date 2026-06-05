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
    private static let onboardingCompletedKey = "LinguistMac.hasCompletedOnboarding"

    @Published var settings: AppSettings
    @Published private(set) var recentTranslations: [TranslationResult]
    @Published var popupState: TranslationPopupState
    @Published var quickDraft: QuickTranslateDraft
    @Published var quickSessionState: TranslationSessionState
    @Published var readiness: OnboardingReadinessSnapshot
    @Published private(set) var lastCommand: AppShellCommand?

    let availableLanguages: [TranslationLanguage] = [
        .autoDetect,
        .english,
        .thai,
        .japanese,
        .korean,
        .simplifiedChinese
    ]

    let availableProviders: [TranslationProviderDescriptor] = [
        TranslationProviderDescriptor(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false
        ),
        TranslationProviderDescriptor(
            id: .deepl,
            displayName: "DeepL",
            requiresAPIKey: true,
            usesNetwork: true
        ),
        TranslationProviderDescriptor(
            id: .googleCloud,
            displayName: "Google Cloud",
            requiresAPIKey: true,
            usesNetwork: true
        ),
        TranslationProviderDescriptor(
            id: .microsoftAzure,
            displayName: "Microsoft Azure",
            requiresAPIKey: true,
            usesNetwork: true
        )
    ]

    private let translator: any TranslationProviding
    private let clipboard: any ClipboardServicing

    init(
        settings: AppSettings = AppSettings(),
        recentTranslations: [TranslationResult] = [],
        translator: any TranslationProviding = PreviewTranslationProvider(),
        clipboard: any ClipboardServicing = SystemClipboardService()
    ) {
        var initialSettings = settings
        initialSettings.hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: Self.onboardingCompletedKey
        )

        self.settings = initialSettings
        self.recentTranslations = recentTranslations
        popupState = .empty
        quickDraft = QuickTranslateDraft(
            sourceLanguage: initialSettings.sourceLanguage,
            targetLanguage: initialSettings.targetLanguage
        )
        quickSessionState = .idle
        readiness = OnboardingReadinessSnapshot.make(
            screenRecording: .notDetermined,
            accessibility: .notDetermined,
            appleTranslation: .unknown,
            cloudProviderConfigured: false
        )
        self.translator = translator
        self.clipboard = clipboard
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

    func presentScreenTranslationPreview() {
        record(.screenTranslate)

        let request = TranslationRequest(
            text: "Captured screen text preview",
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage,
            inputMode: .screenSelection,
            providerID: settings.selectedProviderID
        )
        let result = TranslationResult(
            request: request,
            translatedText: "Preview translation for the selected screen text."
        )
        popupState = .success(result, showsOriginal: false)
        saveRecent(result)
    }

    func runQuickTranslate() async {
        do {
            let request = try quickDraft.makeRequest(providerID: settings.selectedProviderID)
            quickSessionState = .translating(request)
            let result = try await translator.translate(request)
            quickSessionState = .completed(result)
            popupState = .success(result, showsOriginal: false)
            saveRecent(result)

            if settings.autoCopyEnabled {
                await clipboard.writeText(result.translatedText)
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

    func togglePopupOriginal() {
        popupState = popupState.toggledOriginalVisibility()
    }

    func copyPopupText() async {
        guard let text = popupState.copyableText else {
            return
        }

        record(.copyTranslation)
        await clipboard.writeText(text)
    }

    func markOnboardingComplete() {
        setOnboardingCompleted(true)
    }

    func setOnboardingCompleted(_ isCompleted: Bool) {
        settings.hasCompletedOnboarding = isCompleted
        UserDefaults.standard.set(isCompleted, forKey: Self.onboardingCompletedKey)
    }

    func reopenOnboarding() {
        record(.onboarding)
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

struct PreviewTranslationProvider: TranslationProviding {
    let id: TranslationProviderID = .apple
    let displayName = "Apple Translation Preview"
    let requiresAPIKey = false
    let usesNetwork = false

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranslationFailure.emptyInput
        }

        return TranslationResult(
            request: request,
            translatedText: "Preview translation: \(text)"
        )
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
