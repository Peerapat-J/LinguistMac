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
            permissionChecker: StubPermissionChecker(
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

private struct ThrowingSpeechToTextService: SpeechToTextServicing {
    let error: any Error & Sendable

    func transcribeShortPhrase(_ request: SpeechRecognitionRequest) async throws -> SpeechRecognitionResult {
        _ = request
        throw error
    }
}

private struct SampleSpeechRecognitionError: Error, Sendable {}
