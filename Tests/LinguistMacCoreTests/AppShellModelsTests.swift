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
        let lookupRequest = WordLookupRequest(
            sourceText: "hello",
            sentenceContext: "hello world",
            sourceLanguage: .english,
            targetLanguage: .thai,
            providerID: .apple
        )
        let wordCard = TranslationPopupWordCardState(
            wordTranslation: WordTranslation(sourceText: "hello", translatedText: "sawasdee"),
            lookupState: .loading(lookupRequest)
        )
        let state = TranslationPopupState.success(result, showsOriginal: false, wordCard: wordCard)

        XCTAssertEqual(state.copyableText, "sawasdee")
        XCTAssertFalse(state.showsOriginal)
        let toggledState = state.toggledOriginalVisibility()
        XCTAssertTrue(toggledState.showsOriginal)
        XCTAssertEqual(toggledState.wordCard, wordCard)
        XCTAssertNil(toggledState.updatingWordCard(nil).wordCard)

        let indexedWordCard = TranslationPopupWordCardState(
            wordTranslation: wordCard.wordTranslation,
            wordIndex: 2,
            lookupState: wordCard.lookupState
        )
        XCTAssertTrue(indexedWordCard.matches(wordCard.wordTranslation, at: 2))
        XCTAssertFalse(indexedWordCard.matches(wordCard.wordTranslation, at: 1))
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

    func testOnboardingReadinessSurfacesVoicePermissionsAsOptional() {
        let readiness = OnboardingReadinessSnapshot.make(
            screenRecording: .granted,
            accessibility: .granted,
            microphone: .denied,
            speechRecognition: .restricted,
            appleTranslation: .ready,
            cloudProviderConfigured: false
        )
        let items = Dictionary(uniqueKeysWithValues: readiness.items.map { ($0.kind, $0) })

        XCTAssertEqual(items[.voiceMicrophone]?.status, .denied)
        XCTAssertEqual(items[.speechRecognition]?.status, .restricted)
        XCTAssertEqual(items[.voiceMicrophone]?.isRequiredForDefaultWorkflow, false)
        XCTAssertEqual(items[.speechRecognition]?.isRequiredForDefaultWorkflow, false)
        XCTAssertEqual(items[.voiceMicrophone]?.showsRecoveryAction, true)
        XCTAssertEqual(items[.speechRecognition]?.showsRecoveryAction, true)
        XCTAssertTrue(readiness.isScreenTranslationReady)
    }

    func testFreshVoicePermissionsShowRecoveryActions() {
        let readiness = OnboardingReadinessSnapshot.make(
            screenRecording: .notDetermined,
            accessibility: .notDetermined,
            microphone: .notDetermined,
            speechRecognition: .notDetermined,
            appleTranslation: .unknown,
            cloudProviderConfigured: false
        )
        let items = Dictionary(uniqueKeysWithValues: readiness.items.map { ($0.kind, $0) })

        XCTAssertEqual(items[.voiceMicrophone]?.showsRecoveryAction, true)
        XCTAssertEqual(items[.speechRecognition]?.showsRecoveryAction, true)
        XCTAssertEqual(items[.screenTranslation]?.showsRecoveryAction, true)
        XCTAssertEqual(items[.accessibility]?.showsRecoveryAction, true)
    }

    func testReadinessStatusTextSurfacesLanguagePackStates() {
        let needsDownload = OnboardingReadinessSnapshot.make(
            screenRecording: .granted,
            accessibility: .notDetermined,
            appleTranslation: .needsDownload,
            cloudProviderConfigured: false
        )
        let unsupported = OnboardingReadinessSnapshot.make(
            screenRecording: .granted,
            accessibility: .notDetermined,
            appleTranslation: .unavailable,
            cloudProviderConfigured: true
        )

        let downloadItems = Dictionary(uniqueKeysWithValues: needsDownload.items.map { ($0.kind, $0) })
        let unsupportedItems = Dictionary(uniqueKeysWithValues: unsupported.items.map { ($0.kind, $0) })

        XCTAssertEqual(downloadItems[.appleTranslation]?.statusText, "Needs Download")
        XCTAssertEqual(downloadItems[.appleTranslation]?.status, .notDetermined)
        XCTAssertEqual(unsupportedItems[.appleTranslation]?.statusText, "Unsupported")
        XCTAssertEqual(unsupportedItems[.cloudProvider]?.statusText, "Ready")
    }

    func testAppleLanguagePackCurrentPairRequiresConcreteDifferentLanguages() {
        XCTAssertEqual(
            AppleLanguagePackPair.current(
                settings: AppSettings(sourceLanguage: .thai, targetLanguage: .english)
            ),
            AppleLanguagePackPair(sourceLanguage: .thai, targetLanguage: .english)
        )
        XCTAssertNil(
            AppleLanguagePackPair.current(
                settings: AppSettings(sourceLanguage: .autoDetect, targetLanguage: .english)
            )
        )
        XCTAssertNil(
            AppleLanguagePackPair.current(
                settings: AppSettings(sourceLanguage: .english, targetLanguage: .english)
            )
        )
    }

    func testAppleLanguagePackCatalogExcludesAutoDetect() {
        let languages = AppleLanguagePackCatalog.supportedLanguages(
            from: TranslationLanguageCatalog.defaultLanguages
        )

        XCTAssertFalse(languages.contains(where: \.supportsAutoDetect))
        XCTAssertEqual(
            languages,
            TranslationLanguageCatalog.defaultLanguages.filter { !$0.supportsAutoDetect }
        )
    }

    func testAppleLanguagePackSelectionOnlyPreparesNeedsDownloadPair() {
        let pair = AppleLanguagePackPair(sourceLanguage: .english, targetLanguage: .thai)
        let needsDownload = AppleLanguagePackSelection(
            pair: pair,
            readiness: .needsDownload
        )
        let preparing = AppleLanguagePackSelection(
            pair: pair,
            readiness: .needsDownload,
            isPreparing: true
        )
        let ready = AppleLanguagePackSelection(
            pair: pair,
            readiness: .ready
        )
        let noPair = AppleLanguagePackSelection(
            pair: nil,
            readiness: .needsDownload
        )

        XCTAssertTrue(needsDownload.canPrepare)
        XCTAssertFalse(preparing.canPrepare)
        XCTAssertFalse(ready.canPrepare)
        XCTAssertFalse(noPair.canPrepare)
        XCTAssertFalse(needsDownload.hasPreparationFailure)
        XCTAssertTrue(
            AppleLanguagePackSelection(
                pair: pair,
                readiness: .needsDownload,
                message: "Apple Translation could not prepare this language pair.",
                messageKind: .failure
            ).hasPreparationFailure
        )
        XCTAssertTrue(
            AppleLanguagePackSelection(
                pair: pair,
                readiness: .needsDownload,
                message: "Download not completed yet. Try again later.",
                messageKind: .notCompleted
            ).hasIncompletePreparation
        )
        XCTAssertFalse(
            AppleLanguagePackSelection(
                pair: pair,
                readiness: .needsDownload,
                message: "Download canceled. Try Download again.",
                messageKind: .canceled
            ).hasPreparationFailure
        )
        XCTAssertEqual(LanguagePackReadiness.needsDownload.displayText, "Needs Download")
    }

    func testFailurePresentationMapsRecoveryActionsAndRedactsProviderMessage() {
        XCTAssertEqual(
            TranslationFailure.permissionDenied(.screenRecording).presentation.recoveryAction,
            .openSystemSettings(.screenRecording)
        )
        XCTAssertEqual(
            TranslationFailure.permissionDenied(.screenRecording).presentation.message,
            "Screen Recording permission is needed before this workflow can run. "
                + "If it is already enabled in System Settings, quit and reopen LinguistMac so macOS applies it."
        )
        XCTAssertEqual(
            TranslationFailure.permissionDenied(.speechRecognition).presentation.recoveryAction,
            .openSystemSettings(.speechRecognition)
        )
        XCTAssertEqual(
            TranslationFailure.missingAPIKey(.deepl).presentation.recoveryAction,
            .openSettings
        )
        XCTAssertEqual(
            TranslationFailure.voiceCaptureCancelled.presentation.recoveryAction,
            .retry
        )
        XCTAssertEqual(
            TranslationFailure.speechSourceLanguageRequired.presentation.message,
            "Choose a source language before using voice capture. Speech recognition does not support Auto Detect."
        )
        XCTAssertEqual(
            TranslationFailure.onDeviceSpeechUnavailable.presentation.message,
            "The selected source language does not support on-device speech recognition. "
                + "Choose another source language before using voice capture."
        )
        XCTAssertEqual(
            TranslationFailure.noSpeechRecognized.presentation.message,
            "No spoken phrase was recognized. Try speaking again."
        )
        XCTAssertEqual(
            TranslationFailure.speechRecognitionFailed.presentation.recoveryAction,
            .retry
        )

        let providerFailure = TranslationFailure.providerFailed("secret-token-123 source text")

        XCTAssertFalse(providerFailure.presentation.message.contains("secret-token-123"))
        XCTAssertFalse(providerFailure.presentation.message.contains("source text"))
        XCTAssertEqual(providerFailure.presentation.recoveryAction, .openSettings)
    }

    func testWordLookupFailurePresentationMapsRecoverableFailures() {
        XCTAssertNil(WordLookupFailure.cancelled.presentation.recoveryAction)
        XCTAssertEqual(
            WordLookupFailure.missingLanguagePack(.apple).presentation.recoveryAction,
            .openSettings
        )
        XCTAssertEqual(
            WordLookupFailure.providerFailed.presentation.message,
            "The translation provider could not complete the word lookup. Check configuration or try again."
        )
        XCTAssertEqual(WordLookupFailure.providerFailed.presentation.recoveryAction, .retry)
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
