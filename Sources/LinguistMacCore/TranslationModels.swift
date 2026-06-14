import Foundation
import NaturalLanguage

public struct TranslationLanguage: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let supportsAutoDetect: Bool

    public init(
        id: String,
        displayName: String,
        supportsAutoDetect: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsAutoDetect = supportsAutoDetect
    }
}

public extension TranslationLanguage {
    static let autoDetect = TranslationLanguage(
        id: "auto",
        displayName: "Auto Detect",
        supportsAutoDetect: true
    )

    static let english = TranslationLanguage(id: "en", displayName: "English")
    static let thai = TranslationLanguage(id: "th", displayName: "Thai")
    static let japanese = TranslationLanguage(id: "ja", displayName: "Japanese")
    static let korean = TranslationLanguage(id: "ko", displayName: "Korean")
    static let simplifiedChinese = TranslationLanguage(id: "zh-Hans", displayName: "Chinese Simplified")
}

public extension TranslationLanguage {
    var canBeTargetLanguage: Bool {
        !supportsAutoDetect
    }
}

public struct TranslationProviderID: Codable, RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension TranslationProviderID {
    static let apple = TranslationProviderID(rawValue: "apple")
    static let deepl = TranslationProviderID(rawValue: "deepl")
    static let googleCloud = TranslationProviderID(rawValue: "google-cloud")
    static let microsoftAzure = TranslationProviderID(rawValue: "microsoft-azure")

    static let allKnownProviders: [TranslationProviderID] = [
        .apple,
        .deepl,
        .googleCloud,
        .microsoftAzure
    ]

    static let cloudProviders: [TranslationProviderID] = [
        .deepl,
        .googleCloud,
        .microsoftAzure
    ]

    static func knownProvider(rawValue: String) -> TranslationProviderID? {
        let providerID = TranslationProviderID(rawValue: rawValue)
        return allKnownProviders.contains(providerID) ? providerID : nil
    }

    func supports(
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) -> Bool {
        switch self {
        case .deepl:
            sourceLanguage != .thai && targetLanguage != .thai
        default:
            true
        }
    }
}

public struct TranslationProviderDescriptor: Equatable, Sendable {
    public let id: TranslationProviderID
    public let displayName: String
    public let detail: String
    public let requiresAPIKey: Bool
    public let usesNetwork: Bool
    public let configurationStatus: TranslationProviderConfigurationStatus
    public let privacySummary: String

    public init(
        id: TranslationProviderID,
        displayName: String,
        requiresAPIKey: Bool,
        usesNetwork: Bool,
        detail: String = "",
        configurationStatus: TranslationProviderConfigurationStatus? = nil,
        privacySummary: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.requiresAPIKey = requiresAPIKey
        self.usesNetwork = usesNetwork
        self.configurationStatus = configurationStatus ?? (requiresAPIKey ? .needsAPIKey : .ready)
        self.privacySummary = privacySummary
    }

    public var isConfigured: Bool {
        switch configurationStatus {
        case .ready:
            true
        case .needsAPIKey, .unavailable:
            false
        }
    }
}

public enum TranslationProviderConfigurationStatus: Equatable, Sendable {
    case ready
    case needsAPIKey
    case unavailable(String)

    public var displayText: String {
        switch self {
        case .ready:
            "Ready"
        case .needsAPIKey:
            "API key required"
        case let .unavailable(reason):
            reason
        }
    }
}

public enum TranslationInputMode: String, CaseIterable, Codable, Sendable {
    case screenSelection
    case selectedText
    case clipboardDoubleCopy
    case dragTranslation
    case quickTranslate
}

public extension TranslationInputMode {
    var displayName: String {
        switch self {
        case .screenSelection:
            String(localized: "Screen Translate")
        case .selectedText:
            String(localized: "Selected Text")
        case .clipboardDoubleCopy:
            String(localized: "Cmd+C+C")
        case .dragTranslation:
            String(localized: "Drag Translation")
        case .quickTranslate:
            String(localized: "Quick Translate")
        }
    }
}

public enum ShortcutAction: String, CaseIterable, Sendable {
    case screenTranslation
    case textSelectionTranslation
    case quickTranslate
    case clipboardDoubleCopy
    case dragTranslation
}

public struct CapturedScreenRegion: Equatable, Sendable {
    public let imageData: Data
    public let scale: Double

    public init(imageData: Data, scale: Double = 1) {
        self.imageData = imageData
        self.scale = scale
    }
}

public struct RecognizedText: Equatable, Sendable {
    public let text: String
    public let language: TranslationLanguage?

    public init(text: String, language: TranslationLanguage? = nil) {
        self.text = text
        self.language = language
    }
}

public struct TranslationRequest: Equatable, Sendable {
    public let text: String
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage
    public let inputMode: TranslationInputMode
    public let providerID: TranslationProviderID

    public init(
        text: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        inputMode: TranslationInputMode,
        providerID: TranslationProviderID
    ) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.inputMode = inputMode
        self.providerID = providerID
    }
}

public struct WordTranslation: Codable, Equatable, Sendable {
    public let sourceText: String
    public let translatedText: String

    public init(
        sourceText: String,
        translatedText: String
    ) {
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}

public struct WordLookupRequest: Codable, Equatable, Sendable {
    public let sourceText: String
    public let sentenceContext: String
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage
    public let providerID: TranslationProviderID
    public let inputMode: TranslationInputMode

    public init(
        sourceText: String,
        sentenceContext: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        providerID: TranslationProviderID,
        inputMode: TranslationInputMode = .selectedText
    ) {
        self.sourceText = sourceText
        self.sentenceContext = sentenceContext
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.providerID = providerID
        self.inputMode = inputMode
    }
}

public struct WordLookupResult: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let request: WordLookupRequest
    public let translatedText: String
    public let definition: String?
    public let example: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        request: WordLookupRequest,
        translatedText: String,
        definition: String? = nil,
        example: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.translatedText = translatedText
        self.definition = definition
        self.example = example
        self.createdAt = createdAt
    }
}

public enum WordLookupFailure: Error, Equatable, Sendable {
    case emptySourceText
    case cancelled
    case missingAPIKey(TranslationProviderID)
    case providerUnavailable(TranslationProviderID)
    case unsupportedLanguagePair
    case providerFailed
}

public enum WordLookupState: Equatable, Sendable {
    case idle
    case loading(WordLookupRequest)
    case completed(WordLookupResult)
    case empty(WordLookupRequest)
    case failed(WordLookupFailure)
}

public enum WordTranslationTokenizer {
    public static func words(in text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return []
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmedText

        var words: [String] = []
        tokenizer.enumerateTokens(in: trimmedText.startIndex ..< trimmedText.endIndex) { range, _ in
            let token = String(trimmedText[range])
            if containsWordCharacter(token) {
                words.append(token)
            }
            return true
        }

        return words
    }

    private static func containsWordCharacter(_ token: String) -> Bool {
        token.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }
}

public enum SourceLanguageResolver {
    public static func resolvedSourceLanguage(
        settingsSource: TranslationLanguage,
        sourceText: String,
        recognizedLanguage: TranslationLanguage? = nil
    ) -> TranslationLanguage {
        guard settingsSource.supportsAutoDetect else {
            return settingsSource
        }

        return recognizedLanguage
            ?? detectedLanguage(in: sourceText)
            ?? settingsSource
    }

    public static func detectedLanguage(in text: String) -> TranslationLanguage? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let dominantLanguage = NLLanguageRecognizer.dominantLanguage(for: trimmedText)
        else {
            return nil
        }

        return TranslationLanguageCatalog.language(forID: dominantLanguage.rawValue)
    }
}

public extension TranslationRequest {
    func usingProvider(_ providerID: TranslationProviderID) -> TranslationRequest {
        TranslationRequest(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            inputMode: inputMode,
            providerID: providerID
        )
    }

    func resolvingAutoDetectedSource() -> TranslationRequest {
        guard sourceLanguage.supportsAutoDetect,
              let detectedLanguage = SourceLanguageResolver.detectedLanguage(in: text)
        else {
            return self
        }

        return TranslationRequest(
            text: text,
            sourceLanguage: detectedLanguage,
            targetLanguage: targetLanguage,
            inputMode: inputMode,
            providerID: providerID
        )
    }
}

public struct TranslationResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let request: TranslationRequest
    public let translatedText: String
    public let originalText: String
    public let wordTranslations: [WordTranslation]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        request: TranslationRequest,
        translatedText: String,
        originalText: String? = nil,
        wordTranslations: [WordTranslation] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.translatedText = translatedText
        self.originalText = originalText ?? request.text
        self.wordTranslations = wordTranslations
        self.createdAt = createdAt
    }
}

public enum TranslationFailure: Error, Equatable, Sendable {
    case permissionDenied(PermissionKind)
    case captureCancelled
    case noTextRecognized
    case emptyInput
    case unsupportedLanguagePair
    case missingLanguagePack(TranslationProviderID)
    case providerUnavailable(TranslationProviderID)
    case missingAPIKey(TranslationProviderID)
    case inputModeDisabled(TranslationInputMode)
    case providerFailed(String)
}

public enum TranslationSessionState: Equatable, Sendable {
    case idle
    case requestingPermission(PermissionKind)
    case capturing
    case recognizing
    case translating(TranslationRequest)
    case completed(TranslationResult)
    case failed(TranslationFailure)
}
