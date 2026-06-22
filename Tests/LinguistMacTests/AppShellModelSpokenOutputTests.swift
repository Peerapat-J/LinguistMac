@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelSpokenOutputTests: XCTestCase {
    func testSpeakQuickTranslationUsesCompletedResultWithoutMicrophonePermission() async throws {
        let spokenOutput = SpokenOutputTestService(
            supportedLanguages: [.thai],
            waitsForRelease: true
        )
        let model = AppShellModel(
            services: makeServices(
                permissionChecker: SpokenOutputDeniedPermissionChecker(),
                spokenOutput: spokenOutput
            )
        )
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)
        model.quickSessionState = .completed(result)

        model.speakQuickTranslation()
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await spokenOutput.waitUntilSpeakStarts()

        XCTAssertEqual(
            model.spokenOutputState,
            .speaking(SpokenOutputRequest(text: "สวัสดี", language: .thai))
        )

        await spokenOutput.releaseSpeech()
        await task.value

        let requests = await spokenOutput.capturedRequests()
        XCTAssertEqual(requests, [SpokenOutputRequest(text: "สวัสดี", language: .thai)])
        XCTAssertEqual(model.spokenOutputState, .completed(SpokenOutputRequest(text: "สวัสดี", language: .thai)))
        XCTAssertFalse(model.isSpokenOutputActive(for: result))
    }

    func testSpeakPopupTranslationSurfacesUnsupportedTargetLanguage() async throws {
        let spokenOutput = SpokenOutputTestService(supportedLanguages: [.english])
        let model = AppShellModel(services: makeServices(spokenOutput: spokenOutput))
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)
        model.popupState = .success(result, showsOriginal: false)

        model.speakPopupTranslation()
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await task.value

        XCTAssertEqual(
            model.spokenOutputState,
            .failed(
                .unsupportedLanguage(.thai),
                request: SpokenOutputRequest(text: "สวัสดี", language: .thai)
            )
        )
        XCTAssertEqual(model.spokenOutputFailure(for: result), .unsupportedLanguage(.thai))
        let requests = await spokenOutput.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testStopSpokenOutputCancelsActivePlayback() async throws {
        let spokenOutput = SpokenOutputTestService(
            supportedLanguages: [.thai],
            waitsForRelease: true
        )
        let model = AppShellModel(services: makeServices(spokenOutput: spokenOutput))
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)

        model.speakTranslation(result)
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await spokenOutput.waitUntilSpeakStarts()

        XCTAssertTrue(model.isSpokenOutputActive(for: result))

        model.stopSpokenOutput()
        await task.value

        XCTAssertEqual(model.spokenOutputState, .idle)
        XCTAssertNil(model.activeSpokenOutputID)
        XCTAssertNil(model.activeSpokenOutputResultID)
        XCTAssertNil(model.activeSpokenOutputTask)
        let stopCount = await spokenOutput.stopCallCount()
        XCTAssertEqual(stopCount, 1)
    }

    private func makeServices(
        permissionChecker: any PermissionChecking = SpokenOutputGrantedPermissionChecker(),
        spokenOutput: any SpokenOutputServicing
    ) -> LinguistServices {
        LinguistServices(
            screenCapture: SpokenOutputScreenCaptureService(),
            ocr: SpokenOutputOCRService(),
            translatorRegistry: SpokenOutputTranslationProviderRegistry(),
            languageAvailability: SpokenOutputLanguageAvailabilityChecker(),
            settingsStore: SpokenOutputAppSettingsStore(),
            apiKeyStore: SpokenOutputAPIKeyStore(),
            launchAtLogin: SpokenOutputLaunchAtLoginService(),
            historyStore: SpokenOutputHistoryStore(),
            permissionChecker: permissionChecker,
            clipboard: SpokenOutputClipboard(),
            selectedTextCapture: SpokenOutputSelectedTextCapture(),
            shortcutRegistry: SpokenOutputShortcutRegistry(),
            spokenOutput: spokenOutput
        )
    }
}

private func makeSpokenOutputResult(
    translatedText: String,
    targetLanguage: TranslationLanguage
) -> TranslationResult {
    let request = TranslationRequest(
        text: "hello",
        sourceLanguage: .english,
        targetLanguage: targetLanguage,
        inputMode: .quickTranslate,
        providerID: .apple
    )
    return TranslationResult(request: request, translatedText: translatedText)
}

private actor SpokenOutputTestService: SpokenOutputServicing {
    private let supportedLanguages: Set<TranslationLanguage>
    private let waitsForRelease: Bool
    private var requests: [SpokenOutputRequest] = []
    private var stopCount = 0
    private var didStartSpeaking = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var speechContinuation: CheckedContinuation<Void, Error>?

    init(
        supportedLanguages: Set<TranslationLanguage>,
        waitsForRelease: Bool = false
    ) {
        self.supportedLanguages = supportedLanguages
        self.waitsForRelease = waitsForRelease
    }

    func canSpeak(language: TranslationLanguage) async -> Bool {
        supportedLanguages.contains(language)
    }

    func speak(_ request: SpokenOutputRequest) async throws {
        requests.append(request)
        didStartSpeaking = true
        let continuations = startContinuations
        startContinuations = []
        continuations.forEach { $0.resume() }

        guard waitsForRelease else {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            speechContinuation = continuation
        }
    }

    func stop() async {
        stopCount += 1
        speechContinuation?.resume(throwing: SpokenOutputFailure.cancelled)
        speechContinuation = nil
    }

    func waitUntilSpeakStarts() async {
        guard !didStartSpeaking else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func releaseSpeech() {
        speechContinuation?.resume()
        speechContinuation = nil
    }

    func capturedRequests() -> [SpokenOutputRequest] {
        requests
    }

    func stopCallCount() -> Int {
        stopCount
    }
}

private struct SpokenOutputScreenCaptureService: ScreenCaptureServicing {
    func captureSelection() async throws -> CapturedScreenRegion {
        CapturedScreenRegion(imageData: Data())
    }
}

private struct SpokenOutputOCRService: OCRServicing {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText {
        _ = region
        return RecognizedText(text: "hello")
    }
}

private struct SpokenOutputTranslationProviderRegistry: TranslationProviderRegistry {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        _ = id
        return SpokenOutputTranslationProvider()
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        [
            TranslationProviderDescriptor(
                id: .apple,
                displayName: "Apple Translation",
                requiresAPIKey: false,
                usesNetwork: false
            )
        ]
    }
}

private struct SpokenOutputTranslationProvider: TranslationProviding {
    let id = TranslationProviderID.apple
    let displayName = "Apple Translation"
    let detail = "Spoken output test provider"
    let requiresAPIKey = false
    let usesNetwork = false
    let privacySummary = "On-device"

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        .ready
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(request: request, translatedText: "สวัสดี")
    }
}

private struct SpokenOutputLanguageAvailabilityChecker: LanguageAvailabilityChecking {
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

private actor SpokenOutputAppSettingsStore: AppSettingsStoring {
    func loadSettings() async throws -> AppSettings {
        AppSettings()
    }

    func saveSettings(_ settings: AppSettings) async throws {
        _ = settings
    }
}

private actor SpokenOutputAPIKeyStore: APIKeyStoring {
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

private actor SpokenOutputLaunchAtLoginService: LaunchAtLoginServicing {
    func isEnabled() async -> Bool {
        false
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        _ = isEnabled
    }
}

private actor SpokenOutputHistoryStore: TranslationHistoryStoring {
    func save(_ result: TranslationResult) async throws {
        _ = result
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        _ = limit
        return []
    }
}

private struct SpokenOutputGrantedPermissionChecker: PermissionChecking {
    func status(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .granted
    }
}

private struct SpokenOutputDeniedPermissionChecker: PermissionChecking {
    func status(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .denied
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        _ = kind
        return .denied
    }
}

private actor SpokenOutputClipboard: ClipboardServicing {
    func readText() async -> String? {
        nil
    }

    func writeText(_ text: String) async {
        _ = text
    }
}

private struct SpokenOutputSelectedTextCapture: SelectedTextCapturing {
    func captureSelectedText() async throws -> String {
        "hello"
    }
}

private actor SpokenOutputShortcutRegistry: ShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        _ = shortcut
        _ = action
    }

    func unregister(_ action: ShortcutAction) async {
        _ = action
    }
}
