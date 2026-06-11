import AppKit
import LinguistMacCore

@MainActor
final class KeyboardInputMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    @discardableResult
    func start(
        model: AppShellModel,
        openWindow: @escaping @MainActor (AppWindow) -> Void
    ) -> Bool {
        guard localMonitor == nil, globalMonitor == nil else {
            return false
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            Task { @MainActor in
                await self.handle(event, model: model, openWindow: openWindow)
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak model] event in
            Task { @MainActor in
                await self.handle(event, model: model, openWindow: openWindow)
            }
        }

        return true
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        localMonitor = nil
        globalMonitor = nil
    }

    private func handle(
        _ event: NSEvent,
        model: AppShellModel?,
        openWindow: @escaping @MainActor (AppWindow) -> Void
    ) async {
        guard let model else {
            return
        }

        if event.isCommandC {
            let didTriggerDoubleCopy = await model.observeCopyCommand()
            if didTriggerDoubleCopy {
                openWindow(.translationPopup)
                return
            }
        }

        let settings = model.settings
        if event.matches(settings.screenTranslationShortcut) {
            await model.runScreenTranslation()
            openWindow(.translationPopup)
        } else if event.matches(settings.textSelectionShortcut) {
            await model.runSelectedTextTranslation()
            openWindow(.translationPopup)
        } else if event.matches(settings.quickTranslateShortcut) {
            model.prepareQuickTranslate()
            openWindow(.quickTranslate)
        }
    }
}

private extension NSEvent {
    var isCommandC: Bool {
        charactersIgnoringModifiers?.uppercased() == "C" && normalizedModifiers == [.command]
    }

    func matches(_ shortcut: LinguistMacCore.KeyboardShortcut) -> Bool {
        charactersIgnoringModifiers?.uppercased() == shortcut.key.uppercased()
            && normalizedModifiers == shortcut.modifiers
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
