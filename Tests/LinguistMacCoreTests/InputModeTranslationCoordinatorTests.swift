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

    func testSelectedTextTranslationAddsWordBreakdownForSentences() async throws {
        let historyStore = InMemoryTranslationHistoryStore()
        let clipboard = InMemoryClipboard(text: "original clipboard")
        let provider = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "unused",
            translatedTextsBySource: [
                "hello world": "สวัสดีชาวโลก",
                "hello": "สวัสดี",
                "world": "โลก"
            ]
        )
        let services = makeServices(
            selectedText: .success(" hello world "),
            translatorRegistry: StubTranslationProviderRegistry(provider: provider),
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

        XCTAssertEqual(result.translatedText, "สวัสดีชาวโลก")
        XCTAssertEqual(
            result.wordTranslations,
            [
                WordTranslation(sourceText: "hello", translatedText: "สวัสดี"),
                WordTranslation(sourceText: "world", translatedText: "โลก")
            ]
        )
        let recentHistory = try await historyStore.recent(limit: 1)
        let clipboardText = await clipboard.readText()
        XCTAssertEqual(recentHistory, [result])
        XCTAssertEqual(clipboardText, "สวัสดีชาวโลก")
    }

    func testSelectedTextTranslationAutoDetectsSourceLanguageAndKeepsTargetSetting() async {
        let services = makeServices(
            selectedText: .success("This is a simple English sentence for language detection."),
            translatedText: "sawasdee"
        )
        let settings = AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai)
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateSelectedText(settings: settings)

        guard case let .completed(result) = finalState else {
            return XCTFail("Expected completed state, got \(finalState)")
        }
        XCTAssertEqual(result.request.sourceLanguage, .english)
        XCTAssertEqual(result.request.targetLanguage, .thai)
        XCTAssertEqual(result.request.inputMode, .selectedText)
    }

    func testSelectedTextTranslationFallsBackWhenPreferredProviderCannotTranslateDetectedLanguage() async {
        let apple = StubTranslationProvider(
            id: .apple,
            displayName: "Apple Translation",
            requiresAPIKey: false,
            usesNetwork: false,
            translatedText: "thai"
        )
        let deepl = StubTranslationProvider(
            id: .deepl,
            displayName: "DeepL",
            requiresAPIKey: true,
            usesNetwork: true,
            translatedText: "unused"
        )
        let services = makeServices(
            selectedText: .success("ภาษาไทยสำหรับการตรวจจับภาษาในข้อความที่เลือก"),
            translatorRegistry: DefaultTranslationProviderRegistry(providers: [deepl, apple]),
            translatedText: "unused"
        )
        let settings = AppSettings(
            sourceLanguage: .autoDetect,
            targetLanguage: .english,
            selectedProviderID: .deepl
        )
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateSelectedText(settings: settings)

        guard case let .completed(result) = finalState else {
            return XCTFail("Expected completed state, got \(finalState)")
        }
        XCTAssertEqual(result.request.sourceLanguage, .thai)
        XCTAssertEqual(result.request.targetLanguage, .english)
        XCTAssertEqual(result.request.providerID, .apple)
        XCTAssertEqual(result.translatedText, "thai")
    }

    func testSelectedTextTranslationReportsMissingPackForDetectedLanguage() async {
        let services = makeServices(
            selectedText: .success("This is a simple English sentence for language detection."),
            readiness: .needsDownload
        )
        let settings = AppSettings(sourceLanguage: .autoDetect, targetLanguage: .thai)
        let coordinator = InputModeTranslationCoordinator(services: services)

        let finalState = await coordinator.translateSelectedText(settings: settings)

        XCTAssertEqual(finalState, .failed(.missingLanguagePack(.apple)))
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
        translatorRegistry: (any TranslationProviderRegistry)? = nil,
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
            translatorRegistry: translatorRegistry ?? StubTranslationProviderRegistry(provider: provider),
            languageAvailability: StubLanguageAvailabilityChecker(readiness: readiness),
            settingsStore: InMemoryAppSettingsStore(),
            apiKeyStore: InMemoryAPIKeyStore(),
            launchAtLogin: StubLaunchAtLoginService(),
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
