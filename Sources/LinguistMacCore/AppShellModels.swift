import Foundation

public enum TranslationPopupState: Equatable, Sendable {
    case empty
    case loading(TranslationRequest)
    case success(
        TranslationResult,
        showsOriginal: Bool,
        wordCard: TranslationPopupWordCardState? = nil
    )
    case failed(TranslationFailure, originalText: String?)

    public var copyableText: String? {
        switch self {
        case let .success(result, _, _):
            result.translatedText
        case .empty, .loading, .failed:
            nil
        }
    }

    public var showsOriginal: Bool {
        switch self {
        case let .success(_, showsOriginal, _):
            showsOriginal
        case .empty, .loading, .failed:
            false
        }
    }

    public var wordCard: TranslationPopupWordCardState? {
        switch self {
        case let .success(_, _, wordCard):
            wordCard
        case .empty, .loading, .failed:
            nil
        }
    }

    public func toggledOriginalVisibility() -> TranslationPopupState {
        switch self {
        case let .success(result, showsOriginal, wordCard):
            .success(result, showsOriginal: !showsOriginal, wordCard: wordCard)
        case .empty, .loading, .failed:
            self
        }
    }

    public func updatingWordCard(_ wordCard: TranslationPopupWordCardState?) -> TranslationPopupState {
        switch self {
        case let .success(result, showsOriginal, _):
            .success(result, showsOriginal: showsOriginal, wordCard: wordCard)
        case .empty, .loading, .failed:
            self
        }
    }
}

public struct TranslationPopupWordCardState: Equatable, Sendable {
    public let wordTranslation: WordTranslation
    public let wordIndex: Int?
    public let lookupState: WordLookupState

    public init(
        wordTranslation: WordTranslation,
        wordIndex: Int? = nil,
        lookupState: WordLookupState
    ) {
        self.wordTranslation = wordTranslation
        self.wordIndex = wordIndex
        self.lookupState = lookupState
    }

    public func matches(_ wordTranslation: WordTranslation, at index: Int) -> Bool {
        if let wordIndex {
            return wordIndex == index
        }

        return self.wordTranslation == wordTranslation
    }
}

public enum TranslationRecoveryAction: Equatable, Sendable {
    case openSystemSettings(PermissionKind)
    case openSettings
    case retry
}

public struct TranslationFailurePresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let recoveryAction: TranslationRecoveryAction?

    public init(
        title: String,
        message: String,
        recoveryAction: TranslationRecoveryAction? = nil
    ) {
        self.title = title
        self.message = message
        self.recoveryAction = recoveryAction
    }
}

public extension TranslationFailure {
    var presentation: TranslationFailurePresentation {
        switch self {
        case let .permissionDenied(kind):
            TranslationFailurePresentation(
                title: "Permission Required",
                message: "\(kind.displayName) permission is needed before this workflow can run.",
                recoveryAction: .openSystemSettings(kind)
            )
        case .captureCancelled:
            TranslationFailurePresentation(
                title: "Capture Cancelled",
                message: "The screen capture was cancelled before text could be translated.",
                recoveryAction: .retry
            )
        case .noTextRecognized:
            TranslationFailurePresentation(
                title: "No Text Found",
                message: "No readable text was found in the selected area.",
                recoveryAction: .retry
            )
        case .emptyInput:
            TranslationFailurePresentation(
                title: "No Text To Translate",
                message: "Enter or select text before starting translation."
            )
        case .unsupportedLanguagePair:
            TranslationFailurePresentation(
                title: "Language Pair Unavailable",
                message: "The selected source and target languages are not available for this provider.",
                recoveryAction: .openSettings
            )
        case let .missingLanguagePack(providerID):
            TranslationFailurePresentation(
                title: "Language Pack Needed",
                message: "\(providerID.displayName) needs the required language pack before translating offline.",
                recoveryAction: .openSettings
            )
        case let .providerUnavailable(providerID):
            TranslationFailurePresentation(
                title: "Provider Unavailable",
                message: "\(providerID.displayName) is not available with the current configuration.",
                recoveryAction: .openSettings
            )
        case let .missingAPIKey(providerID):
            TranslationFailurePresentation(
                title: "API Key Required",
                message: "Add an API key for \(providerID.displayName) before using this cloud provider.",
                recoveryAction: .openSettings
            )
        case let .inputModeDisabled(inputMode):
            TranslationFailurePresentation(
                title: "Input Mode Disabled",
                message: "Enable \(inputMode.displayName) in Settings before using this workflow.",
                recoveryAction: .openSettings
            )
        case .providerFailed:
            TranslationFailurePresentation(
                title: "Translation Failed",
                message: "The translation provider could not complete the request. Check configuration or try again.",
                recoveryAction: .openSettings
            )
        }
    }
}

public extension WordLookupFailure {
    var presentation: TranslationFailurePresentation {
        switch self {
        case .emptySourceText:
            TranslationFailurePresentation(
                title: "No Word Selected",
                message: "Choose a word from the translated sentence before opening a word card."
            )
        case .cancelled:
            TranslationFailurePresentation(
                title: "Lookup Cancelled",
                message: "The word lookup was cancelled before it completed."
            )
        case let .missingAPIKey(providerID):
            TranslationFailurePresentation(
                title: "API Key Required",
                message: "Add an API key for \(providerID.displayName) before using this cloud provider.",
                recoveryAction: .openSettings
            )
        case let .missingLanguagePack(providerID):
            TranslationFailurePresentation(
                title: "Language Pack Needed",
                message: "\(providerID.displayName) needs the required language pack before looking up this word.",
                recoveryAction: .openSettings
            )
        case let .providerUnavailable(providerID):
            TranslationFailurePresentation(
                title: "Provider Unavailable",
                message: "\(providerID.displayName) is not available with the current configuration.",
                recoveryAction: .openSettings
            )
        case .unsupportedLanguagePair:
            TranslationFailurePresentation(
                title: "Language Pair Unavailable",
                message: "The selected source and target languages are not available for this provider.",
                recoveryAction: .openSettings
            )
        case .providerFailed:
            TranslationFailurePresentation(
                title: "Word Lookup Failed",
                message: "The translation provider could not complete the word lookup. "
                    + "Check configuration or try again.",
                recoveryAction: .openSettings
            )
        }
    }
}

public enum TranslationHistoryPolicy {
    public static let defaultLimit = 50

    public static func trimmed(
        _ results: [TranslationResult],
        limit: Int = defaultLimit
    ) -> [TranslationResult] {
        guard limit > 0 else {
            return []
        }

        return Array(results
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit))
    }

    public static func inserting(
        _ result: TranslationResult,
        into results: [TranslationResult],
        limit: Int = defaultLimit
    ) -> [TranslationResult] {
        let withoutDuplicate = results.filter { $0.id != result.id }
        return trimmed([result] + withoutDuplicate, limit: limit)
    }
}

public struct QuickTranslateDraft: Equatable, Sendable {
    public var sourceText: String
    public var sourceLanguage: TranslationLanguage
    public var targetLanguage: TranslationLanguage

    public init(
        sourceText: String = "",
        sourceLanguage: TranslationLanguage = .autoDetect,
        targetLanguage: TranslationLanguage = .english
    ) {
        self.sourceText = sourceText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    public var trimmedText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canTranslate: Bool {
        !trimmedText.isEmpty
    }

    public func makeRequest(providerID: TranslationProviderID) throws -> TranslationRequest {
        guard canTranslate else {
            throw TranslationFailure.emptyInput
        }

        return TranslationRequest(
            text: trimmedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            inputMode: .quickTranslate,
            providerID: providerID
        )
    }
}

public extension TranslationProviderID {
    var displayName: String {
        switch self {
        case .apple:
            "Apple Translation"
        case .deepl:
            "DeepL"
        case .googleCloud:
            "Google Cloud Translation"
        case .microsoftAzure:
            "Microsoft Azure Translator"
        default:
            rawValue
        }
    }
}

public extension PermissionKind {
    var displayName: String {
        switch self {
        case .screenRecording:
            "Screen Recording"
        case .accessibility:
            "Accessibility"
        case .keychain:
            "Keychain"
        case .network:
            "Network"
        }
    }
}

public enum LanguagePackReadiness: Equatable, Sendable {
    case unknown
    case ready
    case needsDownload
    case unavailable
}

public enum SetupReadinessKind: String, CaseIterable, Sendable {
    case screenTranslation
    case accessibility
    case appleTranslation
    case cloudProvider
}

public struct OnboardingReadinessItem: Identifiable, Equatable, Sendable {
    public let kind: SetupReadinessKind
    public let title: String
    public let detail: String
    public let status: PermissionStatus
    public let isRequiredForDefaultWorkflow: Bool

    public var id: SetupReadinessKind {
        kind
    }

    public init(
        kind: SetupReadinessKind,
        title: String,
        detail: String,
        status: PermissionStatus,
        isRequiredForDefaultWorkflow: Bool
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.isRequiredForDefaultWorkflow = isRequiredForDefaultWorkflow
    }
}

public struct OnboardingReadinessSnapshot: Equatable, Sendable {
    public let items: [OnboardingReadinessItem]

    public init(items: [OnboardingReadinessItem]) {
        self.items = items
    }

    public var isScreenTranslationReady: Bool {
        items
            .filter(\.isRequiredForDefaultWorkflow)
            .allSatisfy { $0.status == .granted }
    }

    public static func make(
        screenRecording: PermissionStatus,
        accessibility: PermissionStatus,
        appleTranslation: LanguagePackReadiness,
        cloudProviderConfigured: Bool
    ) -> OnboardingReadinessSnapshot {
        OnboardingReadinessSnapshot(
            items: [
                OnboardingReadinessItem(
                    kind: .screenTranslation,
                    title: "Screen Translation",
                    detail: "Screen Recording is needed before selected-region OCR can run.",
                    status: screenRecording,
                    isRequiredForDefaultWorkflow: true
                ),
                OnboardingReadinessItem(
                    kind: .appleTranslation,
                    title: "Apple Translation",
                    detail: languagePackDetail(for: appleTranslation),
                    status: permissionStatus(for: appleTranslation),
                    isRequiredForDefaultWorkflow: true
                ),
                OnboardingReadinessItem(
                    kind: .accessibility,
                    title: "Text Selection",
                    detail: "Accessibility unlocks selected-text, double-copy, and drag workflows later.",
                    status: accessibility,
                    isRequiredForDefaultWorkflow: false
                ),
                OnboardingReadinessItem(
                    kind: .cloudProvider,
                    title: "Cloud Providers",
                    detail: "Optional BYOK providers stay disabled until you configure them.",
                    status: cloudProviderConfigured ? .granted : .notDetermined,
                    isRequiredForDefaultWorkflow: false
                )
            ]
        )
    }

    private static func languagePackDetail(for readiness: LanguagePackReadiness) -> String {
        switch readiness {
        case .unknown:
            "Language pack status will be checked when Apple Translation wiring lands."
        case .ready:
            "On-device Apple Translation language packs are ready."
        case .needsDownload:
            "Download the needed language packs before offline translation."
        case .unavailable:
            "Apple Translation is not available for this language pair yet."
        }
    }

    private static func permissionStatus(for readiness: LanguagePackReadiness) -> PermissionStatus {
        switch readiness {
        case .ready:
            .granted
        case .needsDownload:
            .notDetermined
        case .unknown:
            .notDetermined
        case .unavailable:
            .unavailable
        }
    }
}
