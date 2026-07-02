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
