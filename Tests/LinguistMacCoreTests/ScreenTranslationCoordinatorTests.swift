@testable import LinguistMacCore
import XCTest

final class ScreenTranslationCoordinatorTests: XCTestCase {
    func testCoordinatorCompletesScreenTranslationAndRecordsSideEffects() async throws {
        let region = CapturedScreenRegion(imageData: Data([1, 2, 3]))
        let historyStore = InMemoryTranslationHistoryStore()
        let clipboard = InMemoryClipboard()
        let services = makeServices(
            captureResult: .success(region),
            ocrResult: .success(RecognizedText(text: "  hello  ", language: .english)),
            translatedText: "sawasdee",
            historyStore: historyStore,
            clipboard: clipboard
        )
        let coordinator = ScreenTranslationCoordinator(services: services)
        var settings = AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai)
        settings.autoCopyEnabled = true

        let finalState = await coordinator.translateScreenSelection(settings: settings)

        guard case let .completed(result) = finalState else {
            return XCTFail("Expected completed state, got \(finalState)")
        }

        XCTAssertEqual(result.originalText, "hello")
        XCTAssertEqual(result.translatedText, "sawasdee")
        XCTAssertEqual(result.request.sourceLanguage, .english)
        XCTAssertEqual(result.request.targetLanguage, .thai)
        let recentHistory = try await historyStore.recent(limit: 1)
        let clipboardText = await clipboard.readText()
        XCTAssertEqual(recentHistory, [result])
        XCTAssertEqual(clipboardText, "sawasdee")

        let states = await coordinator.states()
        XCTAssertEqual(states.count, 5)
        XCTAssertEqual(states[0], .idle)
        XCTAssertEqual(states[1], .capturing)
        XCTAssertEqual(states[2], .recognizing)
        guard case .translating = states[3] else {
            return XCTFail("Expected translating state, got \(states[3])")
        }
        XCTAssertEqual(states[4], .completed(result))
    }

    func testCoordinatorFailsWhenScreenRecordingPermissionIsMissing() async {
        let services = makeServices(
            permissionStatus: .notDetermined,
            captureResult: .success(CapturedScreenRegion(imageData: Data([1]))),
            ocrResult: .success(RecognizedText(text: "hello"))
        )
        let coordinator = ScreenTranslationCoordinator(services: services)

        let finalState = await coordinator.translateScreenSelection(settings: AppSettings())

        XCTAssertEqual(finalState, .failed(.permissionDenied(.screenRecording)))
        let states = await coordinator.states()
        XCTAssertEqual(
            states,
            [
                .idle,
                .requestingPermission(.screenRecording),
                .failed(.permissionDenied(.screenRecording))
            ]
        )
    }

    func testCoordinatorFailsWhenOCRFindsNoText() async {
        let services = makeServices(
            captureResult: .success(CapturedScreenRegion(imageData: Data([1]))),
            ocrResult: .success(RecognizedText(text: " \n "))
        )
        let coordinator = ScreenTranslationCoordinator(services: services)

        let finalState = await coordinator.translateScreenSelection(settings: AppSettings())

        XCTAssertEqual(finalState, .failed(.noTextRecognized))
    }

    func testCoordinatorFailsWhenLanguagePackNeedsDownload() async {
        let services = makeServices(
            captureResult: .success(CapturedScreenRegion(imageData: Data([1]))),
            ocrResult: .success(RecognizedText(text: "hello", language: .english)),
            readiness: .needsDownload
        )
        let coordinator = ScreenTranslationCoordinator(services: services)

        let finalState = await coordinator.translateScreenSelection(settings: AppSettings())

        XCTAssertEqual(finalState, .failed(.missingLanguagePack(.apple)))
    }

    private func makeServices(
        permissionStatus: PermissionStatus = .granted,
        captureResult: Result<CapturedScreenRegion, TranslationFailure>,
        ocrResult: Result<RecognizedText, TranslationFailure>,
        readiness: LanguagePackReadiness = .ready,
        translatedText: String = "translated",
        historyStore: InMemoryTranslationHistoryStore = InMemoryTranslationHistoryStore(),
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
            permissionChecker: StubPermissionChecker(statuses: [.screenRecording: permissionStatus]),
            clipboard: clipboard,
            shortcutRegistry: RecordingShortcutRegistry()
        )
    }
}
