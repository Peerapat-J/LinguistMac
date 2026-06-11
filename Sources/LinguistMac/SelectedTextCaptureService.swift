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
        let originalPasteboard = await pasteboardSnapshot()
        let originalChangeCount = await pasteboardChangeCount()

        await MainActor.run {
            sendCopyCommand()
        }

        let didCopySelection = await waitForPasteboardChange(after: originalChangeCount)
        guard didCopySelection else {
            await restorePasteboard(originalPasteboard)
            throw TranslationFailure.emptyInput
        }

        let selectedText = await pasteboardText()

        await restorePasteboard(originalPasteboard)

        let trimmedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedText.isEmpty else {
            throw TranslationFailure.emptyInput
        }

        return trimmedText
    }

    private func waitForPasteboardChange(after changeCount: Int) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + copyDelayNanoseconds
        let pollIntervalNanoseconds = min(max(copyDelayNanoseconds / 10, 1_000_000), 10_000_000)

        while true {
            if await pasteboardChangeCount() != changeCount {
                return true
            }

            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else {
                break
            }

            let remainingNanoseconds = deadline - now
            try? await Task.sleep(nanoseconds: min(pollIntervalNanoseconds, remainingNanoseconds))
        }

        return await pasteboardChangeCount() != changeCount
    }

    private func pasteboardChangeCount() async -> Int {
        await MainActor.run {
            NSPasteboard.general.changeCount
        }
    }

    private func pasteboardSnapshot() async -> PasteboardSnapshot {
        await MainActor.run {
            PasteboardSnapshot(items: NSPasteboard.general.pasteboardItems ?? [])
        }
    }

    private func pasteboardText() async -> String? {
        await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            let restoredItems = snapshot.makePasteboardItems()
            if !restoredItems.isEmpty {
                NSPasteboard.general.writeObjects(restoredItems)
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

private struct PasteboardSnapshot {
    private let items: [PasteboardItemSnapshot]

    init(items: [NSPasteboardItem]) {
        self.items = items.map(PasteboardItemSnapshot.init)
    }

    func makePasteboardItems() -> [NSPasteboardItem] {
        items.compactMap(\.pasteboardItem)
    }
}

private struct PasteboardItemSnapshot {
    private let valuesByType: [(String, Data)]

    init(item: NSPasteboardItem) {
        valuesByType = item.types.compactMap { type in
            guard let data = item.data(forType: type) else {
                return nil
            }

            return (type.rawValue, data)
        }
    }

    var pasteboardItem: NSPasteboardItem? {
        guard !valuesByType.isEmpty else {
            return nil
        }

        let item = NSPasteboardItem()
        for (rawType, data) in valuesByType {
            item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
        }
        return item
    }
}
