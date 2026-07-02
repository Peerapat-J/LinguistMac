import SwiftUI

struct SettingsSearchHighlightedText: SwiftUI.View {
    let text: String
    let searchText: String

    init(_ text: String, searchText: String) {
        self.text = text
        self.searchText = searchText
    }

    var body: some SwiftUI.View {
        SwiftUI.Text(text.highlightedForSettingsSearch(searchText))
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

        var highlightedString = AttributedString(self)

        for token in tokens {
            var searchStart = startIndex

            while searchStart < endIndex {
                guard let foundRange = range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart ..< endIndex
                ) else {
                    break
                }

                let lowerBound = AttributedString.Index(foundRange.lowerBound, within: highlightedString)
                let upperBound = AttributedString.Index(foundRange.upperBound, within: highlightedString)

                if let lowerBound, let upperBound {
                    highlightedString[lowerBound ..< upperBound].backgroundColor = SwiftUI.Color.yellow.opacity(0.38)
                }

                searchStart = foundRange.isEmpty ? index(after: foundRange.lowerBound) : foundRange.upperBound
            }
        }

        return highlightedString
    }
}
