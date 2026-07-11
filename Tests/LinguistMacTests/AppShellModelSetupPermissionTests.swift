@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelSetupPermissionTests: XCTestCase {
    func testFreshVoiceSetupActionsRequestPermissionPrompts() async {
        let permissionChecker = RecordingSetupPermissionChecker(
            statuses: [
                .screenRecording: .granted,
                .accessibility: .granted,
                .microphone: .notDetermined,
                .speechRecognition: .notDetermined
            ],
            requestStatuses: [
                .microphone: .granted,
                .speechRecognition: .granted
            ]
        )
        let model = AppShellModel(services: makeServices(permissionChecker: permissionChecker))

        await model.handleVoicePermissionSetupAction(for: .microphone, currentStatus: .notDetermined)
        await model.handleVoicePermissionSetupAction(for: .speechRecognition, currentStatus: .notDetermined)

        let requestCalls = await permissionChecker.capturedRequestCalls()
        XCTAssertEqual(requestCalls, [.microphone, .speechRecognition])
        let items = Dictionary(uniqueKeysWithValues: model.readiness.items.map { ($0.kind, $0) })
        XCTAssertEqual(items[.voiceMicrophone]?.status, .granted)
        XCTAssertEqual(items[.speechRecognition]?.status, .granted)
    }

    private func makeServices(
        permissionChecker: any PermissionChecking
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: SetupPermissionNoOpService(),
            ocr: SetupPermissionNoOpService(),
            translatorRegistry: SetupPermissionNoOpService(),
            languageAvailability: SetupPermissionNoOpService(),
            settingsStore: SetupPermissionNoOpService(),
            apiKeyStore: SetupPermissionNoOpService(),
            launchAtLogin: SetupPermissionNoOpService(),
            historyStore: SetupPermissionNoOpService(),
            permissionChecker: permissionChecker,
            clipboard: SetupPermissionNoOpService(),
            selectedTextCapture: SetupPermissionNoOpService(),
            shortcutRegistry: SetupPermissionNoOpService(),
            screenTranslationSoundPlayer: NoOpScreenTranslationSoundPlayer(),
            screenTranslationNotifier: NoOpScreenTranslationNotifier()
        )
    }
}

@MainActor
final class PopupRetranslationReviewTests: XCTestCase {
    func testPopupRetranslationRestoresWordTranslationsForEligibleInputModes() async throws {
        for inputMode in [TranslationInputMode.quickTranslate, .selectedText] {
            let provider = PopupRetranslationReviewProvider()
            let model = AppShellModel(
                settings: AppSettings(sourceLanguage: .english, targetLanguage: .japanese),
                services: makeServices(provider: provider)
            )
            model.popupState = .success(
                popupResult(
                    text: "hello world",
                    targetLanguage: .japanese,
                    inputMode: inputMode
                ),
                showsOriginal: true
            )

            model.selectPopupTargetLanguage(.thai)
            let task = try XCTUnwrap(model.activePopupTranslationTask)
            await task.value

            guard case let .success(result, _, _) = model.popupState else {
                return XCTFail("Expected popup retranslation to complete.")
            }

            XCTAssertEqual(
                result.wordTranslations,
                [
                    WordTranslation(sourceText: "hello", translatedText: "สวัสดี"),
                    WordTranslation(sourceText: "world", translatedText: "โลก")
                ]
            )
            let requests = await provider.capturedRequests()
            XCTAssertEqual(requests.map(\.text), ["hello world", "hello", "world"])
            XCTAssertEqual(requests.dropFirst().map(\.requestsReadings), [false, false])
        }
    }

    private func makeServices(
        provider: any TranslationProviding,
        clipboard: any ClipboardServicing = SetupPermissionNoOpService()
    ) -> LinguistServices {
        let noOpService = SetupPermissionNoOpService()
        return LinguistServices(
            screenCapture: noOpService,
            ocr: noOpService,
            translatorRegistry: PopupRetranslationReviewRegistry(provider: provider),
            languageAvailability: noOpService,
            settingsStore: noOpService,
            apiKeyStore: noOpService,
            launchAtLogin: noOpService,
            historyStore: noOpService,
            permissionChecker: noOpService,
            clipboard: clipboard,
            selectedTextCapture: noOpService,
            shortcutRegistry: noOpService,
            screenTranslationSoundPlayer: NoOpScreenTranslationSoundPlayer(),
            screenTranslationNotifier: NoOpScreenTranslationNotifier()
        )
    }

    private func popupResult(
        text: String,
        targetLanguage: TranslationLanguage,
        inputMode: TranslationInputMode
    ) -> TranslationResult {
        TranslationResult(
            request: TranslationRequest(
                text: text,
                sourceLanguage: .english,
                targetLanguage: targetLanguage,
                inputMode: inputMode,
                providerID: .apple
            ),
            translatedText: "ก่อนแปลใหม่"
        )
    }
}

struct SetupPermissionNoOpService {}

extension SetupPermissionNoOpService: ScreenCaptureServicing {
    func captureSelection() async throws -> CapturedScreenRegion {
        throw CancellationError()
    }
}

extension SetupPermissionNoOpService: OCRServicing {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText {
        _ = region
        throw CancellationError()
    }
}

extension SetupPermissionNoOpService: TranslationProviderRegistry {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        throw TranslationFailure.providerUnavailable(id)
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        []
    }
}

extension SetupPermissionNoOpService: LanguageAvailabilityChecking {
    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        _ = source
        _ = target
        _ = sampleText
        return .ready
    }
}

extension SetupPermissionNoOpService: AppSettingsStoring {
    func loadSettings() async throws -> AppSettings {
        AppSettings()
    }

    func saveSettings(_ settings: AppSettings) async throws {
        _ = settings
    }
}

extension SetupPermissionNoOpService: APIKeyStoring {
    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        return nil
    }

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        _ = apiKey
        _ = providerID
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        _ = providerID
    }

    func apiKeyStatus(for providerID: TranslationProviderID) async -> APIKeyStatus {
        _ = providerID
        return .missing
    }

    func apiRegion(for providerID: TranslationProviderID) async throws -> String? {
        _ = providerID
        return nil
    }

    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws {
        _ = apiRegion
        _ = providerID
    }

    func deleteAPIRegion(for providerID: TranslationProviderID) async throws {
        _ = providerID
    }
}

extension SetupPermissionNoOpService: LaunchAtLoginServicing {
    func isEnabled() async -> Bool {
        false
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        _ = isEnabled
    }
}

extension SetupPermissionNoOpService: TranslationHistoryStoring {
    func save(_ result: TranslationResult) async throws {
        _ = result
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        _ = limit
        return []
    }
}

extension SetupPermissionNoOpService: PermissionChecking {
    func status(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }
}

extension SetupPermissionNoOpService: ClipboardServicing {
    func readText() async -> String? {
        nil
    }

    func writeText(_ text: String) async {
        _ = text
    }
}

extension SetupPermissionNoOpService: SelectedTextCapturing {
    func captureSelectedText() async throws -> String {
        throw CancellationError()
    }
}

extension SetupPermissionNoOpService: ShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        _ = shortcut
        _ = action
    }

    func unregister(_ action: ShortcutAction) async {
        _ = action
    }
}

private actor RecordingSetupPermissionChecker: PermissionChecking {
    private var statuses: [PermissionKind: PermissionStatus]
    private let requestStatuses: [PermissionKind: PermissionStatus]
    private var requestCalls: [PermissionKind] = []

    init(
        statuses: [PermissionKind: PermissionStatus],
        requestStatuses: [PermissionKind: PermissionStatus]
    ) {
        self.statuses = statuses
        self.requestStatuses = requestStatuses
    }

    func status(for kind: PermissionKind) async -> PermissionStatus {
        statuses[kind] ?? .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        requestCalls.append(kind)
        let status = requestStatuses[kind] ?? statuses[kind] ?? .granted
        statuses[kind] = status
        return status
    }

    func capturedRequestCalls() -> [PermissionKind] {
        requestCalls
    }
}

private struct PopupRetranslationReviewRegistry: TranslationProviderRegistry {
    let provider: any TranslationProviding

    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        guard id == provider.id else {
            throw TranslationFailure.providerUnavailable(id)
        }

        return provider
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        [
            TranslationProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                requiresAPIKey: provider.requiresAPIKey,
                usesNetwork: provider.usesNetwork
            )
        ]
    }
}

private actor PopupRetranslationReviewProvider: TranslationProviding {
    nonisolated let id = TranslationProviderID.apple
    nonisolated let displayName = "Popup Review Provider"
    nonisolated let detail = "Popup retranslation regression test provider"
    nonisolated let requiresAPIKey = false
    nonisolated let usesNetwork = false
    nonisolated let privacySummary = "Test provider"

    private var requests: [TranslationRequest] = []

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        let translatedText = switch request.text {
        case "hello world": "สวัสดีชาวโลก"
        case "hello": "สวัสดี"
        case "world": "โลก"
        default: request.text
        }
        return TranslationResult(request: request, translatedText: translatedText)
    }

    func capturedRequests() -> [TranslationRequest] {
        requests
    }
}
