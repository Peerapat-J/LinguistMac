@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelVoiceTests: XCTestCase {
    func testQuickVoiceTranslateCapturesTranscriptThenUsesQuickTranslatePipeline() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let speechToText = VoiceTestSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "  spoken phrase  "))
        )
        let provider = VoiceTestTranslationProvider(
            translatedTextsBySource: [
                "spoken phrase": "วลีที่พูด"
            ]
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeVoiceTestServices(
                translatorRegistry: VoiceTestTranslationProviderRegistry(provider: provider),
                historyStore: historyStore,
                speechToText: speechToText
            )
        )

        model.startQuickVoiceCapture()
        let captureTask = model.activeQuickVoiceCaptureTask
        await captureTask?.value

        let requests = await speechToText.capturedRequests()
        XCTAssertEqual(requests, [SpeechRecognitionRequest(sourceLanguage: .english)])
        XCTAssertEqual(model.quickDraft.sourceText, "spoken phrase")
        XCTAssertEqual(model.quickVoiceTranscript, "spoken phrase")
        XCTAssertEqual(model.quickVoiceState, .completed(SpeechRecognitionResult(transcript: "spoken phrase")))
        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["วลีที่พูด"])
        XCTAssertEqual(model.popupState.copyableText, "วลีที่พูด")

        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults.map(\.request.text), ["spoken phrase"])
    }

    func testQuickVoiceTranslateCancellationDoesNotSaveFailedOrPartialTranslation() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let speechToText = VoiceTestSpeechToTextService(result: .failure(.cancelled))
        let model = AppShellModel(
            services: makeVoiceTestServices(
                historyStore: historyStore,
                speechToText: speechToText
            )
        )

        model.startQuickVoiceCapture()
        let captureTask = model.activeQuickVoiceCaptureTask
        await captureTask?.value

        XCTAssertEqual(model.quickVoiceState, .failed(.cancelled))
        XCTAssertEqual(model.quickSessionState, .failed(.voiceCaptureCancelled))
        XCTAssertNil(model.quickVoiceTranscript)
        XCTAssertTrue(model.recentTranslations.isEmpty)
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertTrue(savedResults.isEmpty)
    }

    func testQuickVoiceTranslatePermissionDeniedDoesNotStartSpeechService() async {
        let speechToText = VoiceTestSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "unused"))
        )
        let model = AppShellModel(
            services: makeVoiceTestServices(
                permissionChecker: VoiceTestPermissionChecker(
                    statuses: [.microphone: .denied],
                    requestStatuses: [.microphone: .denied]
                ),
                speechToText: speechToText
            )
        )

        model.startQuickVoiceCapture()
        let captureTask = model.activeQuickVoiceCaptureTask
        await captureTask?.value

        XCTAssertEqual(model.quickVoiceState, .failed(.permissionDenied(.microphone)))
        XCTAssertEqual(model.quickSessionState, .failed(.permissionDenied(.microphone)))
        let requests = await speechToText.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeVoiceTestServices(
        translatorRegistry: (any TranslationProviderRegistry)? = nil,
        historyStore: any TranslationHistoryStoring = VoiceTestTranslationHistoryStore(),
        permissionChecker: any PermissionChecking = VoiceTestPermissionChecker(),
        speechToText: any SpeechToTextServicing = VoiceTestSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "hello"))
        )
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: VoiceTestScreenCaptureService(),
            ocr: VoiceTestOCRService(),
            translatorRegistry: translatorRegistry ?? VoiceTestTranslationProviderRegistry(),
            languageAvailability: VoiceTestLanguageAvailabilityChecker(),
            settingsStore: VoiceTestAppSettingsStore(),
            apiKeyStore: VoiceTestAPIKeyStore(),
            launchAtLogin: VoiceTestLaunchAtLoginService(),
            historyStore: historyStore,
            permissionChecker: permissionChecker,
            clipboard: VoiceTestClipboard(),
            selectedTextCapture: VoiceTestSelectedTextCapture(),
            shortcutRegistry: VoiceTestShortcutRegistry(),
            speechToText: speechToText
        )
    }
}

private actor VoiceTestSpeechToTextService: SpeechToTextServicing {
    private let result: Result<SpeechRecognitionResult, SpeechRecognitionFailure>
    private let progressEvents: [SpeechRecognitionProgress]
    private var requests: [SpeechRecognitionRequest] = []

    init(
        result: Result<SpeechRecognitionResult, SpeechRecognitionFailure>,
        progressEvents: [SpeechRecognitionProgress] = [.recordingFinished]
    ) {
        self.result = result
        self.progressEvents = progressEvents
    }

    func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult {
        requests.append(request)
        for event in progressEvents {
            await progress(event)
        }

        return try result.get()
    }

    func capturedRequests() -> [SpeechRecognitionRequest] {
        requests
    }
}

private struct VoiceTestTranslationProvider: TranslationProviding {
    let id = TranslationProviderID.apple
    let displayName = "Apple Translation"
    let detail = "Voice test provider"
    let requiresAPIKey = false
    let usesNetwork = false
    let privacySummary = "On-device"
    var translatedText = "สวัสดี"
    var translatedTextsBySource: [String: String] = [:]

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(
            request: request,
            translatedText: translatedTextsBySource[request.text] ?? translatedText
        )
    }
}

private struct VoiceTestTranslationProviderRegistry: TranslationProviderRegistry {
    var provider = VoiceTestTranslationProvider()

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

private actor VoiceTestTranslationHistoryStore: TranslationHistoryStoring {
    private var results: [TranslationResult] = []

    func save(_ result: TranslationResult) async throws {
        results = TranslationHistoryPolicy.inserting(result, into: results)
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        TranslationHistoryPolicy.trimmed(results, limit: limit)
    }
}

private struct VoiceTestPermissionChecker: PermissionChecking {
    var statuses: [PermissionKind: PermissionStatus] = [:]
    var requestStatuses: [PermissionKind: PermissionStatus] = [:]

    func status(for kind: PermissionKind) async -> PermissionStatus {
        statuses[kind] ?? .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        requestStatuses[kind] ?? statuses[kind] ?? .granted
    }
}

private struct VoiceTestScreenCaptureService: ScreenCaptureServicing {
    func captureSelection() async throws -> CapturedScreenRegion {
        CapturedScreenRegion(imageData: Data())
    }
}

private struct VoiceTestOCRService: OCRServicing {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText {
        _ = region
        return RecognizedText(text: "hello")
    }
}

private struct VoiceTestLanguageAvailabilityChecker: LanguageAvailabilityChecking {
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

private actor VoiceTestAppSettingsStore: AppSettingsStoring {
    func loadSettings() async throws -> AppSettings {
        AppSettings()
    }

    func saveSettings(_ settings: AppSettings) async throws {
        _ = settings
    }
}

private actor VoiceTestAPIKeyStore: APIKeyStoring {
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

private actor VoiceTestLaunchAtLoginService: LaunchAtLoginServicing {
    func isEnabled() async -> Bool {
        false
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        _ = isEnabled
    }
}

private actor VoiceTestClipboard: ClipboardServicing {
    func readText() async -> String? {
        nil
    }

    func writeText(_ text: String) async {
        _ = text
    }
}

private struct VoiceTestSelectedTextCapture: SelectedTextCapturing {
    func captureSelectedText() async throws -> String {
        "hello"
    }
}

private actor VoiceTestShortcutRegistry: ShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        _ = shortcut
        _ = action
    }

    func unregister(_ action: ShortcutAction) async {
        _ = action
    }
}
