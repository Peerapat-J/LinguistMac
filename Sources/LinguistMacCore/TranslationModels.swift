import Foundation
import NaturalLanguage

public struct TranslationLanguage: Equatable, Hashable, Sendable {
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

public struct TranslationProviderID: RawRepresentable, Equatable, Hashable, Sendable {
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
}

public struct TranslationProviderDescriptor: Equatable, Sendable {
    public let id: TranslationProviderID
    public let displayName: String
    public let requiresAPIKey: Bool
    public let usesNetwork: Bool

    public init(
        id: TranslationProviderID,
        displayName: String,
        requiresAPIKey: Bool,
        usesNetwork: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.requiresAPIKey = requiresAPIKey
        self.usesNetwork = usesNetwork
    }
}

public enum TranslationInputMode: String, CaseIterable, Sendable {
    case screenSelection
    case selectedText
    case clipboardDoubleCopy
    case dragTranslation
    case quickTranslate
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

public enum SourceLanguageResolver {
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
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        request: TranslationRequest,
        translatedText: String,
        originalText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.translatedText = translatedText
        self.originalText = originalText ?? request.text
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
