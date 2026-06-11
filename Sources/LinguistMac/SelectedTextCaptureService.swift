import AppKit
import CoreGraphics
import Foundation
import LinguistMacCore

actor SystemSelectedTextCaptureService: SelectedTextCapturing {
    private let copyDelayNanoseconds: UInt64

    init(copyDelayNanoseconds: UInt64 = 120_000_000) {
        self.copyDelayNanoseconds = copyDelayNanoseconds
    }

    func captureSelectedText() async throws -> String {
        let originalText = await pasteboardText()

        await MainActor.run {
            sendCopyCommand()
        }

        try? await Task.sleep(nanoseconds: copyDelayNanoseconds)
        let selectedText = await pasteboardText()

        await restorePasteboardText(originalText)

        let trimmedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedText.isEmpty else {
            throw TranslationFailure.emptyInput
        }

        return trimmedText
    }

    private func pasteboardText() async -> String? {
        await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
    }

    private func restorePasteboardText(_ text: String?) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            if let text {
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    @MainActor
    private func sendCopyCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
