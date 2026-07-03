import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import LinguistMacCore

extension ShortcutAction {
    var keyboardShortcutsName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("LinguistMac.\(rawValue)")
    }
}

extension LinguistMacCore.KeyboardShortcut {
    init?(_ shortcut: KeyboardShortcuts.Shortcut) {
        guard let key = ShortcutKeyCode.label(for: shortcut.carbonKeyCode) else {
            return nil
        }

        self.init(
            key: key,
            modifiers: LinguistMacCore.KeyboardModifier.modifiers(from: shortcut.modifiers)
        )
    }

    var keyboardShortcutsShortcut: KeyboardShortcuts.Shortcut? {
        guard let keyCode = ShortcutKeyCode.code(for: key) else {
            return nil
        }

        return KeyboardShortcuts.Shortcut(
            KeyboardShortcuts.Key(rawValue: keyCode),
            modifiers: modifiers.eventModifierFlags
        )
    }
}

private enum ShortcutKeyCode {
    static func label(for keyCode: Int) -> String? {
        labelsByCode[keyCode]
    }

    static func code(for key: String) -> Int? {
        codesByLabel[key.normalizedShortcutKey]
    }

    private static let labelsByCode: [Int: String] = [
        Int(kVK_ANSI_A): "A",
        Int(kVK_ANSI_B): "B",
        Int(kVK_ANSI_C): "C",
        Int(kVK_ANSI_D): "D",
        Int(kVK_ANSI_E): "E",
        Int(kVK_ANSI_F): "F",
        Int(kVK_ANSI_G): "G",
        Int(kVK_ANSI_H): "H",
        Int(kVK_ANSI_I): "I",
        Int(kVK_ANSI_J): "J",
        Int(kVK_ANSI_K): "K",
        Int(kVK_ANSI_L): "L",
        Int(kVK_ANSI_M): "M",
        Int(kVK_ANSI_N): "N",
        Int(kVK_ANSI_O): "O",
        Int(kVK_ANSI_P): "P",
        Int(kVK_ANSI_Q): "Q",
        Int(kVK_ANSI_R): "R",
        Int(kVK_ANSI_S): "S",
        Int(kVK_ANSI_T): "T",
        Int(kVK_ANSI_U): "U",
        Int(kVK_ANSI_V): "V",
        Int(kVK_ANSI_W): "W",
        Int(kVK_ANSI_X): "X",
        Int(kVK_ANSI_Y): "Y",
        Int(kVK_ANSI_Z): "Z",
        Int(kVK_ANSI_0): "0",
        Int(kVK_ANSI_1): "1",
        Int(kVK_ANSI_2): "2",
        Int(kVK_ANSI_3): "3",
        Int(kVK_ANSI_4): "4",
        Int(kVK_ANSI_5): "5",
        Int(kVK_ANSI_6): "6",
        Int(kVK_ANSI_7): "7",
        Int(kVK_ANSI_8): "8",
        Int(kVK_ANSI_9): "9",
        Int(kVK_F1): "F1",
        Int(kVK_F2): "F2",
        Int(kVK_F3): "F3",
        Int(kVK_F4): "F4",
        Int(kVK_F5): "F5",
        Int(kVK_F6): "F6",
        Int(kVK_F7): "F7",
        Int(kVK_F8): "F8",
        Int(kVK_F9): "F9",
        Int(kVK_F10): "F10",
        Int(kVK_F11): "F11",
        Int(kVK_F12): "F12",
        Int(kVK_F13): "F13",
        Int(kVK_F14): "F14",
        Int(kVK_F15): "F15",
        Int(kVK_F16): "F16",
        Int(kVK_F17): "F17",
        Int(kVK_F18): "F18",
        Int(kVK_F19): "F19",
        Int(kVK_F20): "F20",
        Int(kVK_Escape): "Escape",
        Int(kVK_Return): "Return",
        Int(kVK_Space): "Space",
        Int(kVK_Tab): "Tab",
        Int(kVK_Delete): "Delete",
        Int(kVK_ForwardDelete): "ForwardDelete",
        Int(kVK_Home): "Home",
        Int(kVK_End): "End",
        Int(kVK_PageUp): "PageUp",
        Int(kVK_PageDown): "PageDown",
        Int(kVK_LeftArrow): "LeftArrow",
        Int(kVK_RightArrow): "RightArrow",
        Int(kVK_UpArrow): "UpArrow",
        Int(kVK_DownArrow): "DownArrow",
        Int(kVK_ANSI_Minus): "Minus",
        Int(kVK_ANSI_Equal): "Equal",
        Int(kVK_ANSI_LeftBracket): "LeftBracket",
        Int(kVK_ANSI_RightBracket): "RightBracket",
        Int(kVK_ANSI_Backslash): "Backslash",
        Int(kVK_ANSI_Semicolon): "Semicolon",
        Int(kVK_ANSI_Quote): "Quote",
        Int(kVK_ANSI_Comma): "Comma",
        Int(kVK_ANSI_Period): "Period",
        Int(kVK_ANSI_Slash): "Slash",
        Int(kVK_ANSI_Grave): "Backtick"
    ]

    private static let codesByLabel: [String: Int] = Dictionary(
        uniqueKeysWithValues: labelsByCode.map { keyCode, label in
            (label.normalizedShortcutKey, keyCode)
        }
    )
}

private extension String {
    var normalizedShortcutKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private extension LinguistMacCore.KeyboardModifier {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<LinguistMacCore.KeyboardModifier> {
        var modifiers: Set<LinguistMacCore.KeyboardModifier> = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }
}

private extension Set<LinguistMacCore.KeyboardModifier> {
    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) {
            flags.insert(.command)
        }
        if contains(.control) {
            flags.insert(.control)
        }
        if contains(.option) {
            flags.insert(.option)
        }
        if contains(.shift) {
            flags.insert(.shift)
        }
        return flags
    }
}
