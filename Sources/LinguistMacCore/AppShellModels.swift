import Foundation

public enum TranslationPopupState: Equatable, Sendable {
    case empty
    case loading(TranslationRequest)
    case success(TranslationResult, showsOriginal: Bool)
    case failed(TranslationFailure, originalText: String?)

    public var copyableText: String? {
        switch self {
        case let .success(result, _):
            result.translatedText
        case .empty, .loading, .failed:
            nil
        }
    }

    public var showsOriginal: Bool {
        switch self {
        case let .success(_, showsOriginal):
            showsOriginal
        case .empty, .loading, .failed:
            false
        }
    }

    public func toggledOriginalVisibility() -> TranslationPopupState {
        switch self {
        case let .success(result, showsOriginal):
            .success(result, showsOriginal: !showsOriginal)
        case .empty, .loading, .failed:
            self
        }
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
