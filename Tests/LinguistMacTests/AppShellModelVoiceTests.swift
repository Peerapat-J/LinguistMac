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

    func testQuickVoiceTranslateKeepsCaptureActiveUntilTranslationFinishes() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let translationGate = VoiceTranslationGate()
        let speechToText = VoiceTestSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "first phrase"))
        )
        let provider = GatedVoiceTranslationProvider(
            gate: translationGate,
            translatedText: "เสียงแรก"
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
        let captureTask = try XCTUnwrap(model.activeQuickVoiceCaptureTask)
        await translationGate.waitUntilTranslationStarts()

        let activeCaptureID = model.activeQuickVoiceCaptureID
        XCTAssertNotNil(activeCaptureID)
        XCTAssertTrue(model.isQuickVoiceCaptureActive)
        XCTAssertEqual(model.quickVoiceTranscript, "first phrase")
        guard case .translating = model.quickSessionState else {
            await translationGate.releaseTranslation()
            await captureTask.value
            return XCTFail("Expected voice capture to stay active during translation.")
        }

        model.startQuickVoiceCapture()

        XCTAssertEqual(model.activeQuickVoiceCaptureID, activeCaptureID)
        let requestsBeforeRelease = await speechToText.capturedRequests()
        XCTAssertEqual(requestsBeforeRelease, [SpeechRecognitionRequest(sourceLanguage: .english)])

        await translationGate.releaseTranslation()
        await captureTask.value

        XCTAssertFalse(model.isQuickVoiceCaptureActive)
        XCTAssertNil(model.activeQuickVoiceCaptureID)
        XCTAssertNil(model.activeQuickVoiceCaptureTask)
        XCTAssertEqual(model.recentTranslations.map(\.translatedText), ["เสียงแรก"])
        XCTAssertEqual(model.popupState.copyableText, "เสียงแรก")
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults.map(\.translatedText), ["เสียงแรก"])
    }

    func testQuickVoiceTranslateUsesCapturedSourceLanguageWhenPickerChangesDuringCapture() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let speechToText = GatedVoiceSpeechToTextService(
            result: SpeechRecognitionResult(transcript: "spoken phrase")
        )
        let provider = RecordingVoiceTranslationProvider(translatedText: "วลีที่พูด")
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
            services: makeVoiceTestServices(
                translatorRegistry: VoiceTestTranslationProviderRegistry(provider: provider),
                historyStore: historyStore,
                speechToText: speechToText
            )
        )

        model.startQuickVoiceCapture()
        let captureTask = try XCTUnwrap(model.activeQuickVoiceCaptureTask)
        await speechToText.waitUntilCaptureStarts()

        model.quickDraft.sourceLanguage = .japanese
        await speechToText.releaseCapture()
        await captureTask.value

        let speechRequests = await speechToText.capturedRequests()
        XCTAssertEqual(speechRequests, [SpeechRecognitionRequest(sourceLanguage: .english)])
        let translationRequests = await provider.capturedRequests()
        XCTAssertEqual(translationRequests.map(\.sourceLanguage), [.english])
        XCTAssertEqual(model.quickDraft.sourceLanguage, .japanese)
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertEqual(savedResults.map(\.request.sourceLanguage), [.english])
    }

    func testQuickVoiceTranslateRequiresConcreteSourceLanguage() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let speechToText = VoiceTestSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "unused"))
        )
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai),
            services: makeVoiceTestServices(
                historyStore: historyStore,
                speechToText: speechToText
            )
        )

        model.startQuickVoiceCapture()
        let captureTask = model.activeQuickVoiceCaptureTask
        await captureTask?.value

        XCTAssertEqual(model.quickVoiceState, .failed(.sourceLanguageRequired))
        XCTAssertEqual(model.quickSessionState, .failed(.speechSourceLanguageRequired))
        XCTAssertFalse(model.isQuickVoiceCaptureActive)
        XCTAssertNil(model.quickVoiceTranscript)
        let requests = await speechToText.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertTrue(savedResults.isEmpty)
    }

    func testAppleSpeechToTextServiceRejectsAutoDetectSourceLanguage() async {
        let service = AppleSpeechToTextService()

        do {
            _ = try await service.transcribeShortPhrase(
                SpeechRecognitionRequest(sourceLanguage: .autoDetect),
                progress: { _ in }
            )
            XCTFail("Expected Auto Detect speech capture to require a concrete source language.")
        } catch {
            XCTAssertEqual(error as? SpeechRecognitionFailure, .sourceLanguageRequired)
        }
    }

    func testQuickVoiceTranslateSurfacesOnDeviceSpeechUnavailable() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let speechToText = VoiceTestSpeechToTextService(result: .failure(.onDeviceRecognitionUnavailable))
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english),
            services: makeVoiceTestServices(
                historyStore: historyStore,
                speechToText: speechToText
            )
        )

        model.startQuickVoiceCapture()
        let captureTask = model.activeQuickVoiceCaptureTask
        await captureTask?.value

        XCTAssertEqual(model.quickVoiceState, .failed(.onDeviceRecognitionUnavailable))
        XCTAssertEqual(model.quickSessionState, .failed(.onDeviceSpeechUnavailable))
        XCTAssertNil(model.quickVoiceTranscript)
        XCTAssertTrue(model.recentTranslations.isEmpty)
        let savedResults = try await historyStore.recent(limit: 10)
        XCTAssertTrue(savedResults.isEmpty)
    }

    func testQuickVoiceTranslateCancellationDoesNotSaveFailedOrPartialTranslation() async throws {
        let historyStore = VoiceTestTranslationHistoryStore()
        let speechToText = VoiceTestSpeechToTextService(result: .failure(.cancelled))
        let model = AppShellModel(
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
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
            settings: AppSettings(sourceLanguage: .english, targetLanguage: .thai),
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

private actor GatedVoiceSpeechToTextService: SpeechToTextServicing {
    private let result: SpeechRecognitionResult
    private var requests: [SpeechRecognitionRequest] = []
    private var didStartCapture = false
    private var isReleased = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(result: SpeechRecognitionResult) {
        self.result = result
    }

    func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult {
        requests.append(request)
        didStartCapture = true
        let continuations = startContinuations
        startContinuations = []
        continuations.forEach { $0.resume() }

        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }

        await progress(.recordingFinished)
        return result
    }

    func waitUntilCaptureStarts() async {
        guard !didStartCapture else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func releaseCapture() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations = []
        continuations.forEach { $0.resume() }
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

private actor RecordingVoiceTranslationProvider: TranslationProviding {
    nonisolated let id = TranslationProviderID.apple
    nonisolated let displayName = "Apple Translation"
    nonisolated let detail = "Recording voice test provider"
    nonisolated let requiresAPIKey = false
    nonisolated let usesNetwork = false
    nonisolated let privacySummary = "On-device"
    private let translatedText: String
    private var requests: [TranslationRequest] = []

    init(translatedText: String) {
        self.translatedText = translatedText
    }

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        return TranslationResult(request: request, translatedText: translatedText)
    }

    func capturedRequests() -> [TranslationRequest] {
        requests
    }
}

private struct GatedVoiceTranslationProvider: TranslationProviding {
    let id = TranslationProviderID.apple
    let displayName = "Apple Translation"
    let detail = "Gated voice test provider"
    let requiresAPIKey = false
    let usesNetwork = false
    let privacySummary = "On-device"
    let gate: VoiceTranslationGate
    let translatedText: String

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        await gate.translate(request, translatedText: translatedText)
    }
}

private actor VoiceTranslationGate {
    private var didStartTranslation = false
    private var isReleased = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func translate(_ request: TranslationRequest, translatedText: String) async -> TranslationResult {
        didStartTranslation = true
        let continuations = startContinuations
        startContinuations = []
        continuations.forEach { $0.resume() }

        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }

        return TranslationResult(request: request, translatedText: translatedText)
    }

    func waitUntilTranslationStarts() async {
        guard !didStartTranslation else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func releaseTranslation() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations = []
        continuations.forEach { $0.resume() }
    }
}

private struct VoiceTestTranslationProviderRegistry: TranslationProviderRegistry {
    var provider: any TranslationProviding = VoiceTestTranslationProvider()

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
