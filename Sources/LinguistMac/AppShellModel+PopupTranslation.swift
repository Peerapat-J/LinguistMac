import Foundation
import LinguistMacCore

@MainActor
extension AppShellModel {
    var popupSourceLanguage: TranslationLanguage {
        switch popupState {
        case let .success(result, _, _):
            result.request.sourceLanguage
        case let .loading(request):
            request.sourceLanguage
        case .empty, .failed:
            settings.sourceLanguage
        }
    }

    var popupTargetLanguage: TranslationLanguage {
        switch popupState {
        case let .success(result, _, _):
            result.request.targetLanguage
        case let .loading(request):
            request.targetLanguage
        case .empty, .failed:
            settings.targetLanguage
        }
    }

    var canRetranslatePopup: Bool {
        currentPopupTranslationContext?.sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    var canTranslatePopupDraft: Bool {
        !popupSourceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSwapPopupLanguages: Bool {
        guard case let .success(result, _, _) = popupState else {
            return false
        }

        return !isPopupSourceDirty && LanguageSelection(
            source: result.request.sourceLanguage,
            target: result.request.targetLanguage
        ).canSwap && !result.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectPopupSourceLanguage(_ language: TranslationLanguage) {
        startPopupRetranslation(
            sourceLanguage: language,
            targetLanguage: popupTargetLanguage
        )
    }

    func selectPopupTargetLanguage(_ language: TranslationLanguage) {
        startPopupRetranslation(
            sourceLanguage: popupSourceLanguage,
            targetLanguage: language
        )
    }

    func preparePopupSourceEditor(for result: TranslationResult) {
        popupSourceDraft = result.originalText
        isPopupSourceDirty = false
    }

    func preparePopupSourceEditorIfNeeded() {
        guard popupSourceDraft.isEmpty,
              let sourceText = currentPopupTranslationContext?.sourceText
        else {
            return
        }

        popupSourceDraft = sourceText
        isPopupSourceDirty = false
    }

    func updatePopupSourceDraft(_ text: String) {
        popupSourceDraft = text
        isPopupSourceDirty = true
    }

    func clearPopupSourceDraft() {
        updatePopupSourceDraft("")
    }

    func translatePopupDraft() {
        guard canTranslatePopupDraft,
              let currentContext = currentPopupTranslationContext
        else {
            return
        }

        let context = PopupTranslationContext(
            sourceText: popupSourceDraft,
            inputMode: currentContext.inputMode,
            showsOriginal: true
        )
        startPopupRetranslation(
            sourceLanguage: popupSourceLanguage,
            targetLanguage: popupTargetLanguage,
            context: context
        )
    }

    func swapPopupLanguages() {
        guard case let .success(result, _, _) = popupState else {
            return
        }

        var selection = LanguageSelection(
            source: result.request.sourceLanguage,
            target: result.request.targetLanguage
        )
        guard selection.canSwap else {
            return
        }

        selection.swap()
        let context = PopupTranslationContext(
            sourceText: result.translatedText,
            inputMode: result.request.inputMode,
            showsOriginal: true
        )
        popupSourceDraft = result.translatedText
        isPopupSourceDirty = false
        startPopupRetranslation(
            sourceLanguage: selection.source,
            targetLanguage: selection.target,
            context: context
        )
    }

    func cancelPopupRetranslation() {
        activePopupTranslationID = nil
        activePopupTranslationTask?.cancel()
        activePopupTranslationTask = nil
        popupTranslationContext = nil
        popupSourceDraft = ""
        isPopupSourceDirty = false
    }

    private var currentPopupTranslationContext: PopupTranslationContext? {
        switch popupState {
        case let .success(result, showsOriginal, _):
            PopupTranslationContext(
                sourceText: isPopupSourceDirty ? popupSourceDraft : result.originalText,
                inputMode: result.request.inputMode,
                showsOriginal: showsOriginal
            )
        case .loading:
            popupTranslationContext
        case let .failed(_, originalText):
            originalText.map {
                PopupTranslationContext(
                    sourceText: $0,
                    inputMode: popupTranslationContext?.inputMode ?? .quickTranslate,
                    showsOriginal: popupTranslationContext?.showsOriginal ?? true
                )
            }
        case .empty:
            nil
        }
    }

    private func startPopupRetranslation(
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        context contextOverride: PopupTranslationContext? = nil
    ) {
        guard let context = contextOverride ?? currentPopupTranslationContext else {
            return
        }

        setSourceLanguage(sourceLanguage)
        setTargetLanguage(targetLanguage)
        let translationSettings = settingsWithSupportedProvider()
        let request = TranslationRequest(
            text: context.sourceText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            inputMode: context.inputMode,
            providerID: translationSettings.selectedProviderID
        ).resolvingAutoDetectedSource()

        stopSpokenOutput()
        cancelPopupWordLookup()
        activePopupTranslationTask?.cancel()
        let translationID = UUID()
        activePopupTranslationID = translationID
        popupTranslationContext = context
        popupState = .loading(request)

        let task = Task {
            await runPopupRetranslation(
                request,
                context: context,
                translationID: translationID
            )
        }
        activePopupTranslationTask = task
    }

    private func runPopupRetranslation(
        _ initialRequest: TranslationRequest,
        context: PopupTranslationContext,
        translationID: UUID
    ) async {
        do {
            try Task.checkCancellation()
            let providerID = await services.translatorRegistry.supportedProviderID(
                preferred: initialRequest.providerID,
                sourceLanguage: initialRequest.sourceLanguage,
                targetLanguage: initialRequest.targetLanguage
            )
            let request = initialRequest.usingProvider(providerID)
            guard isCurrentPopupTranslation(translationID) else {
                return
            }

            popupState = .loading(request)
            let translator = try await readyTranslator(for: request)
            let result = try await translator.translate(request)
            try Task.checkCancellation()
            guard isCurrentPopupTranslation(translationID) else {
                return
            }

            popupState = .success(result, showsOriginal: context.showsOriginal)
            preparePopupSourceEditor(for: result)
            popupTranslationContext = PopupTranslationContext(
                sourceText: result.originalText,
                inputMode: result.request.inputMode,
                showsOriginal: context.showsOriginal
            )
            saveRecent(result)
            await persistRecentTranslation(result)
            finishPopupTranslation(translationID)
        } catch is CancellationError {
            finishPopupTranslation(translationID)
        } catch let failure as TranslationFailure {
            applyPopupTranslationFailure(failure, context: context, translationID: translationID)
        } catch {
            applyPopupTranslationFailure(
                .providerFailed(error.localizedDescription),
                context: context,
                translationID: translationID
            )
        }
    }

    private func applyPopupTranslationFailure(
        _ failure: TranslationFailure,
        context: PopupTranslationContext,
        translationID: UUID
    ) {
        guard isCurrentPopupTranslation(translationID) else {
            return
        }

        popupState = .failed(failure, originalText: context.sourceText)
        popupTranslationContext = context
        finishPopupTranslation(translationID)
    }

    private func isCurrentPopupTranslation(_ translationID: UUID) -> Bool {
        activePopupTranslationID == translationID && !Task.isCancelled
    }

    private func finishPopupTranslation(_ translationID: UUID) {
        guard activePopupTranslationID == translationID else {
            return
        }

        activePopupTranslationID = nil
        activePopupTranslationTask = nil
    }
}
