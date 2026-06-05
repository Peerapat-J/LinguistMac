@testable import LinguistMacCore
import XCTest

final class AppShellModelsTests: XCTestCase {
    func testPopupStateExposesCopyableTextAndOriginalToggle() {
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )
        let result = TranslationResult(request: request, translatedText: "sawasdee")
        let state = TranslationPopupState.success(result, showsOriginal: false)

        XCTAssertEqual(state.copyableText, "sawasdee")
        XCTAssertFalse(state.showsOriginal)
        XCTAssertTrue(state.toggledOriginalVisibility().showsOriginal)
    }

    func testQuickTranslateDraftBuildsTrimmedRequest() throws {
        let draft = QuickTranslateDraft(
            sourceText: "  hello  ",
            sourceLanguage: .english,
            targetLanguage: .thai
        )

        let request = try draft.makeRequest(providerID: .apple)

        XCTAssertEqual(request.text, "hello")
        XCTAssertEqual(request.inputMode, .quickTranslate)
        XCTAssertEqual(request.sourceLanguage, .english)
        XCTAssertEqual(request.targetLanguage, .thai)
    }

    func testQuickTranslateDraftRejectsEmptyInput() {
        let draft = QuickTranslateDraft(sourceText: " \n ")

        XCTAssertThrowsError(try draft.makeRequest(providerID: .apple)) { error in
            XCTAssertEqual(error as? TranslationFailure, .emptyInput)
        }
    }

    func testOnboardingReadinessRequiresScreenAndAppleTranslation() {
        let ready = OnboardingReadinessSnapshot.make(
            screenRecording: .granted,
            accessibility: .notDetermined,
            appleTranslation: .ready,
            cloudProviderConfigured: false
        )
        let waiting = OnboardingReadinessSnapshot.make(
            screenRecording: .notDetermined,
            accessibility: .granted,
            appleTranslation: .ready,
            cloudProviderConfigured: true
        )

        XCTAssertTrue(ready.isScreenTranslationReady)
        XCTAssertFalse(waiting.isScreenTranslationReady)
    }

    func testDefaultSettingsIncludeM1SurfacePreferences() {
        let settings = AppSettings()

        XCTAssertEqual(settings.popupFontSize, 15)
        XCTAssertEqual(settings.popupWidth, 420)
        XCTAssertTrue(settings.matchPopupWidthToSelection)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }
}
