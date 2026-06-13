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

    func testFailurePresentationMapsRecoveryActionsAndRedactsProviderMessage() {
        XCTAssertEqual(
            TranslationFailure.permissionDenied(.screenRecording).presentation.recoveryAction,
            .openSystemSettings(.screenRecording)
        )
        XCTAssertEqual(
            TranslationFailure.missingAPIKey(.deepl).presentation.recoveryAction,
            .openSettings
        )

        let providerFailure = TranslationFailure.providerFailed("secret-token-123 source text")

        XCTAssertFalse(providerFailure.presentation.message.contains("secret-token-123"))
        XCTAssertFalse(providerFailure.presentation.message.contains("source text"))
        XCTAssertEqual(providerFailure.presentation.recoveryAction, .openSettings)
    }

    func testHistoryPolicyTrimsNewestResultsAndDeduplicatesInsertedResult() {
        let old = makeResult(id: UUID(), text: "old", createdAt: Date(timeIntervalSince1970: 1))
        let middle = makeResult(id: UUID(), text: "middle", createdAt: Date(timeIntervalSince1970: 2))
        let newest = makeResult(id: UUID(), text: "newest", createdAt: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(
            TranslationHistoryPolicy.trimmed([middle, newest, old], limit: 2).map(\.translatedText),
            ["newest", "middle"]
        )

        let replacement = makeResult(id: old.id, text: "replacement", createdAt: Date(timeIntervalSince1970: 4))

        XCTAssertEqual(
            TranslationHistoryPolicy.inserting(replacement, into: [old, middle], limit: 3).map(\.translatedText),
            ["replacement", "middle"]
        )
    }

    func testDefaultSettingsIncludeM1SurfacePreferences() {
        let settings = AppSettings()

        XCTAssertEqual(settings.popupFontSize, 15)
        XCTAssertEqual(settings.popupFontFamily, "")
        XCTAssertEqual(settings.popupWidth, 420)
        XCTAssertEqual(settings.popupHeight, 320)
        XCTAssertTrue(settings.matchPopupWidthToSelection)
        XCTAssertNil(settings.popupOriginX)
        XCTAssertNil(settings.popupOriginY)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    private func makeResult(
        id: UUID,
        text: String,
        createdAt: Date
    ) -> TranslationResult {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )
        return TranslationResult(
            id: id,
            request: request,
            translatedText: text,
            createdAt: createdAt
        )
    }
}
