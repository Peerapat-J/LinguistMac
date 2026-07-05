import AppKit
import LinguistMacCore

@MainActor
final class KeyboardInputMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    @discardableResult
    func start(
        model: AppShellModel,
        shortcutRegistry: SystemShortcutRegistry,
        openWindow: @escaping @MainActor (AppWindow) -> Void
    ) -> Bool {
        guard localMonitor == nil, globalMonitor == nil else {
            return false
        }

        shortcutRegistry.onAction = { [weak model] action in
            Task { @MainActor in
                await self.handle(action, model: model, openWindow: openWindow)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            self.handleCopyCommand(event, model: model, openWindow: openWindow)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak model] event in
            self.handleCopyCommand(event, model: model, openWindow: openWindow)
        }

        return true
    }

    private func handleCopyCommand(
        _ event: NSEvent,
        model: AppShellModel?,
        openWindow: @escaping @MainActor (AppWindow) -> Void
    ) {
        guard event.isCommandC else {
            return
        }

        Task { @MainActor in
            let didTriggerDoubleCopy = await model?.observeCopyCommand() ?? false
            if didTriggerDoubleCopy {
                openWindow(.translationPopup)
            }
        }
    }

    private func handle(
        _ action: ShortcutAction,
        model: AppShellModel?,
        openWindow: @escaping @MainActor (AppWindow) -> Void
    ) async {
        guard let model else {
            return
        }

        switch action {
        case .screenTranslation:
            await model.runScreenTranslation()
            openWindow(.translationPopup)
        case .textSelectionTranslation:
            await model.runSelectedTextTranslation()
            openWindow(.translationPopup)
        case .quickTranslate:
            model.prepareQuickTranslate()
            openWindow(.quickTranslate)
        case .clipboardDoubleCopy, .dragTranslation:
            break
        }
    }
}

private extension NSEvent {
    var isCommandC: Bool {
        charactersIgnoringModifiers?.uppercased() == "C" && normalizedModifiers == [.command]
    }

    var normalizedModifiers: Set<KeyboardModifier> {
        var modifiers: Set<KeyboardModifier> = []
        if modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if modifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }
}
