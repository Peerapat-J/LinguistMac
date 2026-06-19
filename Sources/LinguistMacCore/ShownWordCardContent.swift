import Foundation

public struct ShownWordCardContent: Codable, Equatable, Sendable {
    public let wordTranslation: WordTranslation
    public let wordIndex: Int?
    public let translatedText: String
    public let sentenceContext: String?
    public let definition: String?
    public let example: String?

    public init(
        wordTranslation: WordTranslation,
        wordIndex: Int? = nil,
        translatedText: String,
        sentenceContext: String? = nil,
        definition: String? = nil,
        example: String? = nil
    ) {
        self.wordTranslation = wordTranslation
        self.wordIndex = wordIndex
        self.translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sentenceContext = Self.displayText(sentenceContext)
        self.definition = Self.displayText(definition)
        self.example = Self.displayText(example)
    }

    public init?(
        wordTranslation: WordTranslation,
        wordIndex: Int? = nil,
        lookupResult: WordLookupResult
    ) {
        let translatedText = lookupResult.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else {
            return nil
        }

        self.init(
            wordTranslation: wordTranslation,
            wordIndex: wordIndex,
            translatedText: translatedText,
            sentenceContext: lookupResult.sentenceContextDisplayText,
            definition: lookupResult.definition,
            example: lookupResult.example
        )
    }

    public func matches(_ wordTranslation: WordTranslation, at index: Int?) -> Bool {
        if let wordIndex, let index {
            return wordIndex == index
        }

        return self.wordTranslation == wordTranslation
    }

    private static func displayText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
