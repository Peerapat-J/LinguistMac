@testable import LinguistMacCore
import XCTest

final class InputModeTranslationCoordinatorTests: XCTestCase {
    func testSelectedTextTranslationPreservesPipelineSideEffects() async throws {
        let historyStore = InMemoryTranslationHistoryStore()
        let clipboard = InMemoryClipboard(text: "original clipboard")
        let services = makeServices(
            selectedText: .success("  hello  "),
            translatedText: "sawasdee",
            historyStore: historyStore,
            clipboard: clipboard
        )
        var settings = AppSettings(sourceLanguage: .english, targetLanguage: .thai)
        settings.autoCopyEnabled = true
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateSelectedText(settings: settings)

        guard case let .completed(result) = finalState else {
            return XCTFail("Expected completed state, got \(finalState)")
        }

        XCTAssertEqual(result.request.inputMode, .selectedText)
        XCTAssertEqual(result.originalText, "hello")
        XCTAssertEqual(result.translatedText, "sawasdee")
        let recentHistory = try await historyStore.recent(limit: 1)
        let clipboardText = await clipboard.readText()
        XCTAssertEqual(recentHistory, [result])
        XCTAssertEqual(clipboardText, "sawasdee")
    }

    func testSelectedTextTranslationRequestsAccessibilityPermission() async {
        let services = makeServices(
            accessibilityStatus: .notDetermined,
            requestAccessibilityStatus: .denied,
            selectedText: .success("hello")
        )
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateSelectedText(settings: AppSettings())

        XCTAssertEqual(finalState, .failed(.permissionDenied(.accessibility)))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .requestingPermission(.accessibility),
                .failed(.permissionDenied(.accessibility))
            ]
        )
    }

    func testDoubleCopyTranslationRequiresEnabledSetting() async {
        let services = makeServices(clipboard: InMemoryClipboard(text: "hello"))
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateClipboardDoubleCopy(settings: AppSettings())

        XCTAssertEqual(finalState, .failed(.inputModeDisabled(.clipboardDoubleCopy)))
    }

    func testDoubleCopyTranslationReadsClipboardWhenEnabled() async {
        let services = makeServices(
            translatedText: "sawasdee",
            clipboard: InMemoryClipboard(text: " hello ")
        )
        var settings = AppSettings(sourceLanguage: .english, targetLanguage: .thai)
        settings.doubleCopyTranslationEnabled = true
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateClipboardDoubleCopy(settings: settings)

        guard case let .completed(result) = finalState else {
            return XCTFail("Expected completed state, got \(finalState)")
        }
        XCTAssertEqual(result.request.inputMode, .clipboardDoubleCopy)
        XCTAssertEqual(result.originalText, "hello")
    }

    func testDragTranslationUsesAccessibilityAndScreenCapturePipeline() async {
        let services = makeServices(
            ocrResult: .success(RecognizedText(text: "dragged", language: .english)),
            translatedText: "ลาก"
        )
        var settings = AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai)
        settings.dragTranslationEnabled = true
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateDragSelection(settings: settings)

        guard case let .completed(result) = finalState else {
            return XCTFail("Expected completed state, got \(finalState)")
        }
        XCTAssertEqual(result.request.inputMode, .dragTranslation)
        XCTAssertEqual(result.request.sourceLanguage, .english)
        let states = await coordinator.states()
        XCTAssertEqual(states[1], .capturing)
        XCTAssertEqual(states[2], .recognizing)
    }

    func testDragTranslationCancellationDoesNotContinueToTranslation() async {
        let services = makeServices(captureResult: .failure(.captureCancelled))
        var settings = AppSettings()
        settings.dragTranslationEnabled = true
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateDragSelection(settings: settings)

        XCTAssertEqual(finalState, .failed(.captureCancelled))
    }

    private func makeServices(
        accessibilityStatus: PermissionStatus = .granted,
        requestAccessibilityStatus: PermissionStatus? = nil,
        screenRecordingStatus: PermissionStatus = .granted,
        captureResult: Result<CapturedScreenRegion, TranslationFailure> = .success(
            CapturedScreenRegion(imageData: Data([1]))
        ),
        ocrResult: Result<RecognizedText, TranslationFailure> = .success(
            RecognizedText(text: "hello", language: .english)
        ),
        selectedText: Result<String, TranslationFailure> = .success("hello"),
        readiness: LanguagePackReadiness = .ready,
        translatedText: String = "translated",
        historyStore: any TranslationHistoryStoring = InMemoryTranslationHistoryStore(),
        clipboard: InMemoryClipboard = InMemoryClipboard()
    ) -> LinguistServices {
        let provider = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: translatedText
        )

        return LinguistServices(
            screenCapture: StubScreenCaptureService(result: captureResult),
            ocr: StubOCRService(result: ocrResult),
            translatorRegistry: StubTranslationProviderRegistry(provider: provider),
            languageAvailability: StubLanguageAvailabilityChecker(readiness: readiness),
            settingsStore: InMemoryAppSettingsStore(),
            historyStore: historyStore,
            permissionChecker: StubPermissionChecker(
                statuses: [
                    .accessibility: accessibilityStatus,
                    .screenRecording: screenRecordingStatus
                ],
                requestStatuses: [
                    .accessibility: requestAccessibilityStatus ?? accessibilityStatus,
                    .screenRecording: screenRecordingStatus
                ]
            ),
            clipboard: clipboard,
            selectedTextCapture: StubSelectedTextCapture(result: selectedText),
            shortcutRegistry: RecordingShortcutRegistry()
        )
    }
}
