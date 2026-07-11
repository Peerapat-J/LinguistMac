import AppKit
import LinguistMacCore

@MainActor
extension AppShellModel {
    func isSpokenOutputActive(context: SpokenOutputContext) -> Bool {
        guard activeSpokenOutputContext == context else {
            return false
        }

        switch spokenOutputState {
        case .preparing, .speaking:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    func spokenOutputRequest(
        for role: TranslationTextRole,
        result: TranslationResult,
        textOverride: String? = nil
    ) -> SpokenOutputRequest {
        switch role {
        case .source:
            SpokenOutputRequest(
                text: textOverride ?? result.originalText,
                language: result.request.sourceLanguage
            )
        case .translation:
            SpokenOutputRequest(result: result)
        }
    }

    var savedPopupWindowFrame: CGRect? {
        guard let originX = settings.popupOriginX,
              let originY = settings.popupOriginY
        else {
            return nil
        }

        return CGRect(
            x: originX,
            y: originY,
            width: settings.popupWidth,
            height: settings.popupHeight
        )
    }

    func copyPopupText(
        _ role: TranslationTextRole,
        textOverride: String? = nil
    ) async {
        guard let result = popupState.result else {
            return
        }

        record(.copyTranslation)
        let text = switch role {
        case .source:
            textOverride ?? result.originalText
        case .translation:
            result.translatedText
        }
        await services.clipboard.writeText(text)
    }

    func copyHistoryResult(_ result: TranslationResult) async {
        record(.copyTranslation)
        await services.clipboard.writeText(result.translatedText)
    }

    func showHistoryResult(_ result: TranslationResult) {
        record(.history)
        cancelPopupRetranslation()
        stopSpokenOutput()
        let wordCard = result.shownWordCards.first.map {
            TranslationPopupWordCardState(shownContent: $0, result: result)
        }
        preparePopupSourceEditor(for: result)
        popupState = .success(result, showsOriginal: false, wordCard: wordCard)
    }

    func refreshRecentTranslations(
        limit: Int = TranslationHistoryPolicy.defaultLimit
    ) async {
        do {
            recentTranslations = try await services.historyStore.recent(limit: limit)
            historyLoadError = nil
        } catch {
            historyLoadError = historyLoadFailureMessage(for: error)
        }
    }

    func handleHistoryPersistenceFailure(_ error: Error) {
        NSLog("Translation history persistence failed: %@", error.localizedDescription)
        historyLoadError = HistoryLoadErrorState(
            message: "Translation history could not be saved. Recent translations may be missing after relaunch.",
            diagnosticDescription: historyDiagnosticDescription(for: error)
        )
    }

    func performRecoveryAction(_ action: TranslationRecoveryAction) {
        switch action {
        case let .openSystemSettings(kind):
            openSystemSettings(for: kind)
        case .openSettings:
            record(.settings)
        case .retry:
            Task {
                await retryLastTranslationCommand()
            }
        }
    }

    func rememberPopupWindowFrame(_ frame: CGRect) {
        let width = min(max(frame.width, 320), 720)
        let height = min(max(frame.height, 240), 640)

        guard settings.popupOriginX != frame.origin.x
            || settings.popupOriginY != frame.origin.y
            || settings.popupWidth != width
            || settings.popupHeight != height
        else {
            return
        }

        settings.popupOriginX = frame.origin.x
        settings.popupOriginY = frame.origin.y
        settings.popupWidth = width
        settings.popupHeight = height
    }

    func openSystemSettings(for kind: PermissionKind) {
        record(.openSystemSettings(kind))

        guard let url = systemSettingsURL(for: kind) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func retryLastTranslationCommand() async {
        switch lastCommand {
        case .some(.screenTranslate):
            await runScreenTranslation()
        case .some(.quickTranslate):
            await runQuickTranslate()
        case .some(.selectedTextTranslate):
            await runSelectedTextTranslation()
        case .some(.clipboardDoubleCopyTranslate):
            await runClipboardDoubleCopyTranslation()
        case .some(.dragTranslate):
            await runDragTranslation()
        case .some(.history), .some(.settings), .some(.onboarding), .some(.about), .some(.quit),
             .some(.copyTranslation), .some(.openSystemSettings), nil:
            break
        }
    }

    private func systemSettingsURL(for kind: PermissionKind) -> URL? {
        switch kind {
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .keychain, .network:
            URL(string: "x-apple.systempreferences:com.apple.preference.security")
        }
    }

    private func historyLoadFailureMessage(for error: Error) -> HistoryLoadErrorState {
        let message = "Translation history could not be loaded. Try again or restart LinguistMac."
        return HistoryLoadErrorState(
            message: message,
            diagnosticDescription: historyDiagnosticDescription(for: error)
        )
    }

    private func historyDiagnosticDescription(for error: Error) -> String {
        if let failure = error as? TranslationFailure {
            return failure.presentation.message
        }

        return error.localizedDescription
    }
}
