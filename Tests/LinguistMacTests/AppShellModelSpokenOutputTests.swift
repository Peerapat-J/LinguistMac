@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

@MainActor
final class AppShellModelSpokenOutputTests: XCTestCase {
    func testSpokenOutputVoiceSelectorPrefersExactLanguageIdentifier() {
        let selectedLanguageID = AppleSpokenOutputVoiceSelector.preferredLanguageID(
            for: "zh-Hans",
            availableLanguageIDs: ["zh-Hant", "zh-Hans"]
        )

        XCTAssertEqual(selectedLanguageID, "zh-Hans")
    }

    func testSpokenOutputVoiceSelectorFallsBackToLanguageCodeWhenExactMatchIsUnavailable() {
        let selectedLanguageID = AppleSpokenOutputVoiceSelector.preferredLanguageID(
            for: "en-GB",
            availableLanguageIDs: ["fr-FR", "en-US"]
        )

        XCTAssertEqual(selectedLanguageID, "en-US")
    }

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

        model.speakPopupText(.translation, result: result)
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
        XCTAssertFalse(model.isSpokenOutputActive(context: translationContext(for: result)))
    }

    func testSpeakPopupTranslationSurfacesUnsupportedTargetLanguage() async throws {
        let spokenOutput = SpokenOutputTestService(supportedLanguages: [.english])
        let model = AppShellModel(services: makeServices(spokenOutput: spokenOutput))
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)
        model.popupState = .success(result, showsOriginal: false)

        model.speakPopupText(.translation, result: result)
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await task.value

        XCTAssertEqual(
            model.spokenOutputState,
            .failed(
                .unsupportedLanguage(.thai),
                request: SpokenOutputRequest(text: "สวัสดี", language: .thai)
            )
        )
        let requests = await spokenOutput.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSpeakPopupSourceUsesOriginalTextAndSourceLanguage() async throws {
        let spokenOutput = SpokenOutputTestService(supportedLanguages: [.english])
        let model = AppShellModel(services: makeServices(spokenOutput: spokenOutput))
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)
        model.popupState = .success(result, showsOriginal: true)

        model.speakPopupText(.source, result: result)
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await task.value

        let expectedRequest = SpokenOutputRequest(text: "hello", language: .english)
        let requests = await spokenOutput.capturedRequests()
        XCTAssertEqual(requests, [expectedRequest])
        XCTAssertEqual(model.spokenOutputState, .completed(expectedRequest))
        XCTAssertEqual(
            model.activeSpokenOutputContext,
            SpokenOutputContext(resultID: result.id, role: .source)
        )
    }

    func testPopupCopyUsesTextForRequestedRole() async {
        let clipboard = RecordingSpokenOutputClipboard()
        let model = AppShellModel(
            services: makeServices(
                spokenOutput: SpokenOutputTestService(supportedLanguages: [.english, .thai]),
                clipboard: clipboard
            )
        )
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)
        model.popupState = .success(result, showsOriginal: true)

        await model.copyPopupText(.source)
        await model.copyPopupText(.translation)

        let copiedTexts = await clipboard.capturedTexts()
        XCTAssertEqual(copiedTexts, ["hello", "สวัสดี"])
    }

    func testStopSpokenOutputCancelsActivePlayback() async throws {
        let spokenOutput = SpokenOutputTestService(
            supportedLanguages: [.thai],
            waitsForRelease: true
        )
        let model = AppShellModel(services: makeServices(spokenOutput: spokenOutput))
        let result = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)

        model.speakPopupText(.translation, result: result)
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await spokenOutput.waitUntilSpeakStarts()

        XCTAssertTrue(model.isSpokenOutputActive(context: translationContext(for: result)))

        model.stopSpokenOutput()
        await task.value

        XCTAssertEqual(model.spokenOutputState, .idle)
        XCTAssertNil(model.activeSpokenOutputID)
        XCTAssertNil(model.activeSpokenOutputContext)
        XCTAssertNil(model.activeSpokenOutputTask)
        let stopCount = await spokenOutput.stopCallCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testStartingNewSpokenOutputIgnoresStaleCancellationStop() async throws {
        let spokenOutput = SpokenOutputTestService(
            supportedLanguages: [.thai],
            waitsForRelease: true,
            delaysFirstStopUntilSecondSpeechStarts: true
        )
        let model = AppShellModel(services: makeServices(spokenOutput: spokenOutput))
        let firstResult = makeSpokenOutputResult(translatedText: "สวัสดี", targetLanguage: .thai)
        let secondResult = makeSpokenOutputResult(translatedText: "ขอบคุณ", targetLanguage: .thai)

        model.speakPopupText(.translation, result: firstResult)
        await spokenOutput.waitUntilSpeakStarts(count: 1)

        model.speakPopupText(.translation, result: secondResult)
        await spokenOutput.waitUntilSpeakStarts(count: 2)
        await spokenOutput.waitUntilStopCallCount(1)

        let sessionIDs = await spokenOutput.capturedSessionIDs()
        XCTAssertEqual(sessionIDs.count, 2)
        let firstSessionID = try XCTUnwrap(sessionIDs.first)
        let secondSessionID = try XCTUnwrap(sessionIDs.dropFirst().first)
        let stoppedSessionIDs = await spokenOutput.stoppedSessionIDs()
        XCTAssertEqual(stoppedSessionIDs, [firstSessionID])
        XCTAssertEqual(
            model.spokenOutputState,
            .speaking(SpokenOutputRequest(text: "ขอบคุณ", language: .thai))
        )
        XCTAssertFalse(model.isSpokenOutputActive(context: translationContext(for: firstResult)))
        XCTAssertTrue(model.isSpokenOutputActive(context: translationContext(for: secondResult)))

        await spokenOutput.releaseSpeech(sessionID: secondSessionID)
        let task = try XCTUnwrap(model.activeSpokenOutputTask)
        await task.value

        XCTAssertEqual(
            model.spokenOutputState,
            .completed(SpokenOutputRequest(text: "ขอบคุณ", language: .thai))
        )
    }

    private func makeServices(
        permissionChecker: any PermissionChecking = SpokenOutputGrantedPermissionChecker(),
        spokenOutput: any SpokenOutputServicing,
        clipboard: any ClipboardServicing = SpokenOutputClipboard()
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
            clipboard: clipboard,
            selectedTextCapture: SpokenOutputSelectedTextCapture(),
            shortcutRegistry: SpokenOutputShortcutRegistry(),
            spokenOutput: spokenOutput
        )
    }

    private func translationContext(for result: TranslationResult) -> SpokenOutputContext {
        SpokenOutputContext(resultID: result.id, role: .translation)
    }
}

@MainActor
final class ScreenTranslationFeedbackTests: XCTestCase {
    func testScreenTranslateSuccessPlaysSoundAndPostsNotificationWhenEnabled() async {
        let soundPlayer = RecordingScreenTranslationSoundPlayer(soundNames: ["Glass", "Ping"])
        let notifier = RecordingScreenTranslationNotifier(authorizationStatus: .authorized)
        let model = AppShellModel(
            settings: AppSettings(
                screenTranslationSoundEnabled: true,
                screenTranslationSoundName: "Ping",
                screenTranslationNotificationsEnabled: true
            ),
            services: makeFeedbackServices(
                soundPlayer: soundPlayer,
                notifier: notifier
            )
        )

        await model.runScreenTranslation()

        let playedSounds = await soundPlayer.playedSoundNames()
        let postedResults = await notifier.postedResults()
        XCTAssertEqual(playedSounds, ["Ping"])
        XCTAssertEqual(postedResults.map(\.originalText), ["hello"])
        XCTAssertEqual(postedResults.map(\.translatedText), ["สวัสดี"])
    }

    func testQuickTranslateDoesNotPlayScreenTranslationFeedback() async {
        let soundPlayer = RecordingScreenTranslationSoundPlayer(soundNames: ["Glass"])
        let notifier = RecordingScreenTranslationNotifier(authorizationStatus: .authorized)
        let model = AppShellModel(
            settings: AppSettings(
                screenTranslationSoundEnabled: true,
                screenTranslationNotificationsEnabled: true
            ),
            services: makeFeedbackServices(
                soundPlayer: soundPlayer,
                notifier: notifier
            )
        )
        model.quickDraft.sourceText = "hello"

        await model.runQuickTranslate()

        let playedSounds = await soundPlayer.playedSoundNames()
        let postedResults = await notifier.postedResults()
        XCTAssertTrue(playedSounds.isEmpty)
        XCTAssertTrue(postedResults.isEmpty)
    }

    func testScreenTranslateDoesNotPostNotificationWhenPermissionIsDenied() async {
        let notifier = RecordingScreenTranslationNotifier(authorizationStatus: .denied)
        let model = AppShellModel(
            settings: AppSettings(screenTranslationNotificationsEnabled: true),
            services: makeFeedbackServices(notifier: notifier)
        )

        await model.runScreenTranslation()

        let postedResults = await notifier.postedResults()
        XCTAssertTrue(postedResults.isEmpty)
    }

    func testEnablingNotificationRevertsSettingWhenPermissionIsDenied() async {
        let notifier = RecordingScreenTranslationNotifier(
            authorizationStatus: .notDetermined,
            requestStatus: .denied
        )
        let model = AppShellModel(services: makeFeedbackServices(notifier: notifier))

        await model.setScreenTranslationNotificationsEnabled(true)

        XCTAssertFalse(model.settings.screenTranslationNotificationsEnabled)
        XCTAssertEqual(
            model.screenTranslationNotificationMessage,
            "Notifications are disabled in macOS Settings."
        )
    }

    private func makeFeedbackServices(
        soundPlayer: any ScreenTranslationSoundPlaying = NoOpScreenTranslationSoundPlayer(),
        notifier: any ScreenTranslationNotificationPosting = NoOpScreenTranslationNotifier()
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
            permissionChecker: SpokenOutputGrantedPermissionChecker(),
            clipboard: SpokenOutputClipboard(),
            selectedTextCapture: SpokenOutputSelectedTextCapture(),
            shortcutRegistry: SpokenOutputShortcutRegistry(),
            screenTranslationSoundPlayer: soundPlayer,
            screenTranslationNotifier: notifier
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
    private let delaysFirstStopUntilSecondSpeechStarts: Bool
    private var requests: [SpokenOutputRequest] = []
    private var sessionIDs: [UUID] = []
    private var stopSessionIDs: [UUID] = []
    private var stopCount = 0
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var stopContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    private var speechContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(
        supportedLanguages: Set<TranslationLanguage>,
        waitsForRelease: Bool = false,
        delaysFirstStopUntilSecondSpeechStarts: Bool = false
    ) {
        self.supportedLanguages = supportedLanguages
        self.waitsForRelease = waitsForRelease
        self.delaysFirstStopUntilSecondSpeechStarts = delaysFirstStopUntilSecondSpeechStarts
    }

    func canSpeak(language: TranslationLanguage) async -> Bool {
        supportedLanguages.contains(language)
    }

    func speak(_ request: SpokenOutputRequest, sessionID: UUID) async throws {
        requests.append(request)
        sessionIDs.append(sessionID)
        let continuations = startContinuations
        startContinuations = []
        continuations.forEach { $0.resume() }

        guard waitsForRelease else {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            speechContinuations[sessionID] = continuation
        }
    }

    func stop(sessionID: UUID) async {
        stopCount += 1
        stopSessionIDs.append(sessionID)
        resumeStopContinuations()

        let shouldDelayStop = delaysFirstStopUntilSecondSpeechStarts && stopCount == 1
        if shouldDelayStop {
            await waitUntilSpeakStarts(count: 2)
        }

        speechContinuations.removeValue(forKey: sessionID)?
            .resume(throwing: SpokenOutputFailure.cancelled)
    }

    func waitUntilSpeakStarts() async {
        await waitUntilSpeakStarts(count: 1)
    }

    func waitUntilSpeakStarts(count: Int) async {
        guard requests.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func waitUntilStopCallCount(_ count: Int) async {
        guard stopCount < count else {
            return
        }

        await withCheckedContinuation { continuation in
            stopContinuations.append((count, continuation))
        }
    }

    func releaseSpeech() {
        guard let sessionID = sessionIDs.last else {
            return
        }

        releaseSpeech(sessionID: sessionID)
    }

    func releaseSpeech(sessionID: UUID) {
        speechContinuations.removeValue(forKey: sessionID)?.resume()
    }

    func capturedRequests() -> [SpokenOutputRequest] {
        requests
    }

    func capturedSessionIDs() -> [UUID] {
        sessionIDs
    }

    func stoppedSessionIDs() -> [UUID] {
        stopSessionIDs
    }

    func stopCallCount() -> Int {
        stopCount
    }

    private func resumeStopContinuations() {
        let readyContinuations = stopContinuations.filter { stopCount >= $0.0 }
        stopContinuations.removeAll { stopCount >= $0.0 }
        readyContinuations.forEach { $0.1.resume() }
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

private actor RecordingSpokenOutputClipboard: ClipboardServicing {
    private var texts: [String] = []

    func readText() async -> String? {
        texts.last
    }

    func writeText(_ text: String) async {
        texts.append(text)
    }

    func capturedTexts() -> [String] {
        texts
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

private actor RecordingScreenTranslationSoundPlayer: ScreenTranslationSoundPlaying {
    private let soundNames: [String]
    private var playedSounds: [String] = []

    init(soundNames: [String]) {
        self.soundNames = soundNames
    }

    func availableSoundNames() async -> [String] {
        soundNames
    }

    func playSound(named soundName: String) async {
        playedSounds.append(soundName)
    }

    func playedSoundNames() -> [String] {
        playedSounds
    }
}

private actor RecordingScreenTranslationNotifier: ScreenTranslationNotificationPosting {
    private var status: ScreenTranslationNotificationStatus
    private let requestStatusValue: ScreenTranslationNotificationStatus
    private var results: [TranslationResult] = []

    init(
        authorizationStatus: ScreenTranslationNotificationStatus,
        requestStatus: ScreenTranslationNotificationStatus? = nil
    ) {
        status = authorizationStatus
        requestStatusValue = requestStatus ?? authorizationStatus
    }

    func authorizationStatus() async -> ScreenTranslationNotificationStatus {
        status
    }

    func requestAuthorization() async -> ScreenTranslationNotificationStatus {
        status = requestStatusValue
        return requestStatusValue
    }

    func postScreenTranslation(result: TranslationResult) async {
        results.append(result)
    }

    func openNotificationSettings() async {}

    func postedResults() -> [TranslationResult] {
        results
    }
}
