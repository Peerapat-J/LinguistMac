import AppKit
import SwiftUI

struct SettingsSearchHighlightedText: View {
    let text: String
    let searchText: String

    init(_ text: String, searchText: String) {
        self.text = text
        self.searchText = searchText
    }

    var body: some View {
        Text(text.highlightedForSettingsSearch(searchText))
    }
}

extension SettingsSectionID {
    var searchTerms: [String] {
        switch self {
        case .general:
            [
                title,
                "App",
                "App language",
                "Language",
                "Menu Bar Icon",
                "Launch at login",
                "Auto copy result to clipboard",
                "Auto-copy",
                "Drag translation",
                "Selected text translation",
                "Double copy",
                "Cmd+C+C",
                "Shortcut",
                "Enable Shortcut",
                "Screen translate",
                "Quick translate",
                "Selected text translate"
            ]
        case .translation:
            [
                title,
                "Translation Engine",
                "Engine",
                "Provider",
                "Apple Translation",
                "Cloud translation",
                "Source language",
                "Source",
                "Target language",
                "Target",
                "Language"
            ]
        case .appearance:
            [
                title,
                "Font family",
                "Font size",
                "Font",
                "Width",
                "Height",
                "Popup",
                "Match selection width"
            ]
        case .notification:
            [
                title,
                "Sound",
                "Play completion sound",
                "Screen Translate Sound",
                "System Notification",
                "Show completion notification",
                "Badge Notification"
            ]
        case .api:
            [
                title,
                "Provider Keys",
                "API key",
                "DeepL",
                "Google Cloud Translation",
                "Microsoft Azure Translator",
                "Azure region",
                "Region",
                "Save",
                "Test",
                "Clear"
            ]
        case .setup:
            [
                title,
                "Setup guide",
                "Open Setup Guide",
                "Screen Translation",
                "Screen Recording",
                "Apple Translation",
                "Text Selection",
                "Accessibility",
                "Voice Microphone",
                "Speech Recognition",
                "Cloud Providers",
                "Permission",
                "Ready",
                "Not set up"
            ]
        case .privacy:
            [
                title,
                "History store",
                "Translation history",
                "Provider keys",
                "Keychain",
                "API settings",
                "Local data",
                "Application Support"
            ]
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !tokens.isEmpty else {
            return true
        }

        let searchableText = searchTerms.joined(separator: " ")
        return tokens.allSatisfy {
            searchableText.localizedCaseInsensitiveContains($0)
        }
    }
}

private extension String {
    var settingsSearchTokens: [String] {
        split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func highlightedForSettingsSearch(_ searchText: String) -> AttributedString {
        let tokens = searchText.settingsSearchTokens
        guard !tokens.isEmpty else {
            return AttributedString(self)
        }

        let highlightedString = NSMutableAttributedString(string: self)
        let searchableString = self as NSString

        for token in tokens {
            var searchRange = NSRange(location: 0, length: searchableString.length)

            while searchRange.location < searchableString.length {
                let foundRange = searchableString.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )

                guard foundRange.location != NSNotFound else {
                    break
                }

                highlightedString.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.38),
                    range: foundRange
                )

                let nextLocation = foundRange.location + max(foundRange.length, 1)
                searchRange = NSRange(
                    location: nextLocation,
                    length: searchableString.length - nextLocation
                )
            }
        }

        return AttributedString(highlightedString)
    }
}
