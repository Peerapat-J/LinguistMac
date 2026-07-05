@testable import LinguistMacCore
import XCTest

final class SpeechRecognitionCoordinatorTests: XCTestCase {
    func testCaptureShortPhraseCompletesWithTrimmedTranscript() async {
        let speechToText = RecordingSpeechToTextService(
            result: .success(
                SpeechRecognitionResult(
                    transcript: "  hello world  ",
                    language: .english
                )
            )
        )
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(speechToText: speechToText)
        )

        let finalState = await coordinator.captureShortPhrase(sourceLanguage: .english)

        let expectedResult = SpeechRecognitionResult(
            transcript: "hello world",
            language: .english
        )
        XCTAssertEqual(finalState, .completed(expectedResult))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .capturing,
                .recognizing,
                .completed(expectedResult)
            ]
        )
        let requests = await speechToText.capturedRequests()
        XCTAssertEqual(requests, [SpeechRecognitionRequest(sourceLanguage: .english)])
        XCTAssertEqual(requests.first?.localeIdentifier, "en")
    }

    func testCaptureShortPhraseKeepsCapturingStateWhileServiceRecords() async {
        let expectedResult = SpeechRecognitionResult(
            transcript: "hello world",
            language: .english
        )
        let speechToText = ControlledSpeechToTextService(result: expectedResult)
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(speechToText: speechToText)
        )

        let task = Task {
            await coordinator.captureShortPhrase(sourceLanguage: .english)
        }
        await speechToText.waitUntilCaptureStarted()

        let recordingState = await coordinator.state
        XCTAssertEqual(recordingState, .capturing)

        await speechToText.finishCapture()
        await speechToText.waitUntilRecognitionStarted()

        let recognitionState = await coordinator.state
        XCTAssertEqual(recognitionState, .recognizing)

        await speechToText.finishRecognition()
        let finalState = await task.value

        XCTAssertEqual(finalState, .completed(expectedResult))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .capturing,
                .recognizing,
                .completed(expectedResult)
            ]
        )
    }

    func testCaptureShortPhraseRejectsOverlappingCaptureWithoutChangingActiveState() async {
        let expectedResult = SpeechRecognitionResult(
            transcript: "hello world",
            language: .english
        )
        let speechToText = ControlledSpeechToTextService(result: expectedResult)
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(speechToText: speechToText)
        )

        let firstTask = Task {
            await coordinator.captureShortPhrase(sourceLanguage: .english)
        }
        await speechToText.waitUntilCaptureStarted()

        let secondState = await coordinator.captureShortPhrase(sourceLanguage: .thai)

        XCTAssertEqual(secondState, .failed(.captureInProgress))
        let activeState = await coordinator.state
        XCTAssertEqual(activeState, .capturing)
        let requestsDuringOverlap = await speechToText.capturedRequests()
        XCTAssertEqual(requestsDuringOverlap, [SpeechRecognitionRequest(sourceLanguage: .english)])

        await speechToText.finishCapture()
        await speechToText.waitUntilRecognitionStarted()
        await speechToText.finishRecognition()
        let firstState = await firstTask.value

        XCTAssertEqual(firstState, .completed(expectedResult))
        let finalRequests = await speechToText.capturedRequests()
        XCTAssertEqual(finalRequests, [SpeechRecognitionRequest(sourceLanguage: .english)])
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .capturing,
                .recognizing,
                .completed(expectedResult)
            ]
        )
    }

    func testCaptureShortPhraseFailsForEmptyTranscript() async {
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                speechToText: RecordingSpeechToTextService(
                    result: .success(SpeechRecognitionResult(transcript: " \n "))
                )
            )
        )

        let finalState = await coordinator.captureShortPhrase()

        XCTAssertEqual(finalState, .failed(.emptyTranscript))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .capturing,
                .recognizing,
                .failed(.emptyTranscript)
            ]
        )
    }

    func testCaptureShortPhraseStopsWhenMicrophonePermissionIsDenied() async {
        let speechToText = RecordingSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "unused"))
        )
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                microphoneStatus: .notDetermined,
                requestMicrophoneStatus: .denied,
                speechToText: speechToText
            )
        )

        let finalState = await coordinator.captureShortPhrase()

        XCTAssertEqual(finalState, .failed(.permissionDenied(.microphone)))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .requestingPermission(.microphone),
                .failed(.permissionDenied(.microphone))
            ]
        )
        let requests = await speechToText.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testCaptureShortPhraseStopsWhenSpeechRecognitionPermissionIsDenied() async {
        let speechToText = RecordingSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "unused"))
        )
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                speechRecognitionStatus: .notDetermined,
                requestSpeechRecognitionStatus: .denied,
                speechToText: speechToText
            )
        )

        let finalState = await coordinator.captureShortPhrase()

        XCTAssertEqual(finalState, .failed(.permissionDenied(.speechRecognition)))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .requestingPermission(.speechRecognition),
                .failed(.permissionDenied(.speechRecognition))
            ]
        )
        let requests = await speechToText.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testCaptureShortPhraseSurfacesCancellation() async {
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                speechToText: RecordingSpeechToTextService(result: .failure(.cancelled))
            )
        )

        let finalState = await coordinator.captureShortPhrase()

        XCTAssertEqual(finalState, .failed(.cancelled))
    }

    func testCaptureShortPhraseMapsUnexpectedRecognitionFailureWithoutDiagnostics() async {
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                speechToText: ThrowingSpeechToTextService(error: SampleSpeechRecognitionError())
            )
        )

        let finalState = await coordinator.captureShortPhrase()

        XCTAssertEqual(finalState, .failed(.recognitionFailed))
    }

    private func makeServices(
        microphoneStatus: PermissionStatus = .granted,
        requestMicrophoneStatus: PermissionStatus? = nil,
        speechRecognitionStatus: PermissionStatus = .granted,
        requestSpeechRecognitionStatus: PermissionStatus? = nil,
        permissionChecker: (any PermissionChecking)? = nil,
        speechToText: any SpeechToTextServicing
    ) -> LinguistServices {
        let provider = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "translated"
        )

        return LinguistServices(
            screenCapture: StubScreenCaptureService(
                result: .success(CapturedScreenRegion(imageData: Data([1])))
            ),
            ocr: StubOCRService(result: .success(RecognizedText(text: "hello"))),
            translatorRegistry: StubTranslationProviderRegistry(provider: provider),
            languageAvailability: StubLanguageAvailabilityChecker(readiness: .ready),
            settingsStore: InMemoryAppSettingsStore(),
            apiKeyStore: InMemoryAPIKeyStore(),
            launchAtLogin: StubLaunchAtLoginService(),
            historyStore: InMemoryTranslationHistoryStore(),
            permissionChecker: permissionChecker ?? StubPermissionChecker(
                statuses: [
                    .microphone: microphoneStatus,
                    .speechRecognition: speechRecognitionStatus
                ],
                requestStatuses: [
                    .microphone: requestMicrophoneStatus ?? microphoneStatus,
                    .speechRecognition: requestSpeechRecognitionStatus ?? speechRecognitionStatus
                ]
            ),
            clipboard: InMemoryClipboard(),
            selectedTextCapture: StubSelectedTextCapture(result: .success("selected text")),
            shortcutRegistry: RecordingShortcutRegistry(),
            speechToText: speechToText
        )
    }
}

final class SpeechRecognitionCancelTests: XCTestCase {
    func testCancelledCaptureDoesNotRequestVoicePermissions() async {
        let permissionChecker = ControlledPermissionChecker(
            statuses: [
                .microphone: .notDetermined,
                .speechRecognition: .notDetermined
            ],
            requestStatuses: [
                .microphone: .granted,
                .speechRecognition: .granted
            ]
        )
        let speechToText = RecordingSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "unused"))
        )
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                permissionChecker: permissionChecker,
                speechToText: speechToText
            )
        )
        let startGate = StartGate()
        let task = Task {
            await startGate.wait()
            return await coordinator.captureShortPhrase()
        }

        task.cancel()
        await startGate.open()
        let finalState = await task.value

        XCTAssertEqual(finalState, .failed(.cancelled))
        let statusCalls = await permissionChecker.capturedStatusCalls()
        let requestCalls = await permissionChecker.capturedRequestCalls()
        let requests = await speechToText.capturedRequests()
        XCTAssertTrue(statusCalls.isEmpty)
        XCTAssertTrue(requestCalls.isEmpty)
        XCTAssertTrue(requests.isEmpty)
        let states = await coordinator.states()
        XCTAssertEqual(states, [.idle, .failed(.cancelled)])
    }

    func testCancellationDuringMicrophonePromptDoesNotRequestSpeechRecognitionPermission() async {
        let permissionChecker = ControlledPermissionChecker(
            statuses: [
                .microphone: .notDetermined,
                .speechRecognition: .notDetermined
            ],
            requestStatuses: [
                .speechRecognition: .granted
            ],
            pendingRequestKinds: [.microphone]
        )
        let speechToText = RecordingSpeechToTextService(
            result: .success(SpeechRecognitionResult(transcript: "unused"))
        )
        let coordinator = SpeechRecognitionCoordinator(
            services: makeServices(
                permissionChecker: permissionChecker,
                speechToText: speechToText
            )
        )
        let task = Task {
            await coordinator.captureShortPhrase()
        }
        await permissionChecker.waitUntilRequestStarted(.microphone)

        task.cancel()
        await permissionChecker.finishRequest(.microphone, status: .granted)
        let finalState = await task.value

        XCTAssertEqual(finalState, .failed(.cancelled))
        let statusCalls = await permissionChecker.capturedStatusCalls()
        let requestCalls = await permissionChecker.capturedRequestCalls()
        let requests = await speechToText.capturedRequests()
        XCTAssertEqual(statusCalls, [.microphone])
        XCTAssertEqual(requestCalls, [.microphone])
        XCTAssertTrue(requests.isEmpty)
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .requestingPermission(.microphone),
                .failed(.cancelled)
            ]
        )
    }

    private func makeServices(
        permissionChecker: any PermissionChecking,
        speechToText: any SpeechToTextServicing
    ) -> LinguistServices {
        let provider = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "translated"
        )

        return LinguistServices(
            screenCapture: StubScreenCaptureService(
                result: .success(CapturedScreenRegion(imageData: Data([1])))
            ),
            ocr: StubOCRService(result: .success(RecognizedText(text: "hello"))),
            translatorRegistry: StubTranslationProviderRegistry(provider: provider),
            languageAvailability: StubLanguageAvailabilityChecker(readiness: .ready),
            settingsStore: InMemoryAppSettingsStore(),
            apiKeyStore: InMemoryAPIKeyStore(),
            launchAtLogin: StubLaunchAtLoginService(),
            historyStore: InMemoryTranslationHistoryStore(),
            permissionChecker: permissionChecker,
            clipboard: InMemoryClipboard(),
            selectedTextCapture: StubSelectedTextCapture(result: .success("selected text")),
            shortcutRegistry: RecordingShortcutRegistry(),
            speechToText: speechToText
        )
    }
}

private struct ThrowingSpeechToTextService: SpeechToTextServicing {
    let error: any Error & Sendable

    func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult {
        _ = request
        await progress(.recordingFinished)
        throw error
    }
}

private struct SampleSpeechRecognitionError: Error {}

private actor ControlledSpeechToTextService: SpeechToTextServicing {
    private let result: SpeechRecognitionResult
    private var requests: [SpeechRecognitionRequest] = []
    private var captureStartedContinuation: CheckedContinuation<Void, Never>?
    private var finishCaptureContinuation: CheckedContinuation<Void, Never>?
    private var recognitionStartedContinuation: CheckedContinuation<Void, Never>?
    private var finishRecognitionContinuation: CheckedContinuation<Void, Never>?
    private var hasStartedCapture = false
    private var hasStartedRecognition = false

    init(result: SpeechRecognitionResult) {
        self.result = result
    }

    func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult {
        requests.append(request)
        hasStartedCapture = true
        captureStartedContinuation?.resume()
        captureStartedContinuation = nil

        await withCheckedContinuation { continuation in
            finishCaptureContinuation = continuation
        }

        await progress(.recordingFinished)
        hasStartedRecognition = true
        recognitionStartedContinuation?.resume()
        recognitionStartedContinuation = nil

        await withCheckedContinuation { continuation in
            finishRecognitionContinuation = continuation
        }

        return result
    }

    func capturedRequests() -> [SpeechRecognitionRequest] {
        requests
    }

    func waitUntilCaptureStarted() async {
        guard !hasStartedCapture else {
            return
        }

        await withCheckedContinuation { continuation in
            captureStartedContinuation = continuation
        }
    }

    func finishCapture() {
        finishCaptureContinuation?.resume()
        finishCaptureContinuation = nil
    }

    func waitUntilRecognitionStarted() async {
        guard !hasStartedRecognition else {
            return
        }

        await withCheckedContinuation { continuation in
            recognitionStartedContinuation = continuation
        }
    }

    func finishRecognition() {
        finishRecognitionContinuation?.resume()
        finishRecognitionContinuation = nil
    }
}

private actor ControlledPermissionChecker: PermissionChecking {
    private let statuses: [PermissionKind: PermissionStatus]
    private let requestStatuses: [PermissionKind: PermissionStatus]
    private let pendingRequestKinds: Set<PermissionKind>
    private var statusCalls: [PermissionKind] = []
    private var requestCalls: [PermissionKind] = []
    private var pendingRequestContinuations: [PermissionKind: CheckedContinuation<PermissionStatus, Never>] = [:]
    private var requestStartedContinuations: [PermissionKind: [CheckedContinuation<Void, Never>]] = [:]

    init(
        statuses: [PermissionKind: PermissionStatus],
        requestStatuses: [PermissionKind: PermissionStatus] = [:],
        pendingRequestKinds: Set<PermissionKind> = []
    ) {
        self.statuses = statuses
        self.requestStatuses = requestStatuses
        self.pendingRequestKinds = pendingRequestKinds
    }

    func status(for kind: PermissionKind) async -> PermissionStatus {
        statusCalls.append(kind)
        return statuses[kind] ?? .notDetermined
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        requestCalls.append(kind)
        guard pendingRequestKinds.contains(kind) else {
            return requestStatuses[kind] ?? statuses[kind] ?? .notDetermined
        }

        return await withCheckedContinuation { continuation in
            pendingRequestContinuations[kind] = continuation
            resumeRequestStartedContinuations(for: kind)
        }
    }

    func capturedStatusCalls() -> [PermissionKind] {
        statusCalls
    }

    func capturedRequestCalls() -> [PermissionKind] {
        requestCalls
    }

    func waitUntilRequestStarted(_ kind: PermissionKind) async {
        guard requestCalls.contains(kind) else {
            await withCheckedContinuation { continuation in
                requestStartedContinuations[kind, default: []].append(continuation)
            }
            return
        }
    }

    func finishRequest(_ kind: PermissionKind, status: PermissionStatus) {
        guard let continuation = pendingRequestContinuations.removeValue(forKey: kind) else {
            return
        }

        continuation.resume(returning: status)
    }

    private func resumeRequestStartedContinuations(for kind: PermissionKind) {
        let continuations = requestStartedContinuations.removeValue(forKey: kind) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor StartGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingContinuations = continuations
        continuations = []
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}
