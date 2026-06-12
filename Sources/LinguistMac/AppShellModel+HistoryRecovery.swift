import AppKit
import LinguistMacCore

@MainActor
extension AppShellModel {
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

    func copyPopupText() async {
        guard let text = popupState.copyableText else {
            return
        }

        record(.copyTranslation)
        await services.clipboard.writeText(text)
    }

    func copyHistoryResult(_ result: TranslationResult) async {
        record(.copyTranslation)
        await services.clipboard.writeText(result.translatedText)
    }

    func showHistoryResult(_ result: TranslationResult) {
        record(.history)
        popupState = .success(result, showsOriginal: false)
    }

    func refreshRecentTranslations(
        limit: Int = TranslationHistoryPolicy.defaultLimit
    ) async {
        guard let results = try? await services.historyStore.recent(limit: limit) else {
            return
        }

        recentTranslations = results
    }

    func performRecoveryAction(_ action: TranslationRecoveryAction) {
        switch action {
        case let .openSystemSettings(kind):
            openSystemSettings(for: kind)
        case .openSettings:
            openSettingsWindow()
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

    func resizePopup(widthDelta: Double, heightDelta: Double) {
        settings.popupWidth = min(max(settings.popupWidth + widthDelta, 320), 720)
        settings.popupHeight = min(max(settings.popupHeight + heightDelta, 240), 640)
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
        case .keychain, .network:
            URL(string: "x-apple.systempreferences:com.apple.preference.security")
        }
    }
}
