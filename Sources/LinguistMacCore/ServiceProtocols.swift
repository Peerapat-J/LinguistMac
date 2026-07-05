import Foundation

public protocol ScreenCaptureServicing: Sendable {
    func captureSelection() async throws -> CapturedScreenRegion
}

public protocol OCRServicing: Sendable {
    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText
}

public protocol TranslationProviding: Sendable {
    var id: TranslationProviderID { get }
    var displayName: String { get }
    var detail: String { get }
    var requiresAPIKey: Bool { get }
    var usesNetwork: Bool { get }
    var privacySummary: String { get }

    func configurationStatus() async -> TranslationProviderConfigurationStatus
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

public protocol TranslationProviderRegistry: Sendable {
    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding
    func availableProviders() async -> [TranslationProviderDescriptor]
}

public extension TranslationProviderRegistry {
    func supportedProviderID(
        preferred providerID: TranslationProviderID,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) async -> TranslationProviderID {
        let providers = await availableProviders()
        let supportedProviders = providers.filter {
            $0.id.supports(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        }

        if supportedProviders.contains(where: { $0.id == providerID }) {
            return providerID
        }

        return supportedProviders.first?.id ?? providerID
    }
}

public protocol WordLookupProviding: Sendable {
    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult?
}

public struct ProviderBackedWordLookupService: WordLookupProviding {
    private let translatorRegistry: any TranslationProviderRegistry

    public init(translatorRegistry: any TranslationProviderRegistry) {
        self.translatorRegistry = translatorRegistry
    }

    public func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        let normalizedRequest = normalized(request)
        guard !normalizedRequest.sourceText.isEmpty else {
            throw WordLookupFailure.emptySourceText
        }

        do {
            try Task.checkCancellation()
            let provider = try await translatorRegistry.provider(for: normalizedRequest.providerID)
            let translationRequest = TranslationRequest(
                text: providerLookupText(for: normalizedRequest),
                sourceLanguage: normalizedRequest.sourceLanguage,
                targetLanguage: normalizedRequest.targetLanguage,
                inputMode: normalizedRequest.inputMode,
                providerID: normalizedRequest.providerID
            )
            let result = try await provider.translate(translationRequest)
            let translatedText = displayText(from: result.translatedText)
            guard !translatedText.isEmpty else {
                return nil
            }

            return WordLookupResult(
                request: normalizedRequest,
                translatedText: translatedText
            )
        } catch {
            throw wordLookupFailure(from: error, providerID: normalizedRequest.providerID)
        }
    }

    private func normalized(_ request: WordLookupRequest) -> WordLookupRequest {
        WordLookupRequest(
            sourceText: request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            sentenceContext: request.sentenceContext.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            providerID: request.providerID,
            inputMode: request.inputMode
        )
    }

    private func providerLookupText(for request: WordLookupRequest) -> String {
        guard !request.sentenceContext.isEmpty,
              request.sentenceContext != request.sourceText
        else {
            return request.sourceText
        }

        return "\(request.sourceText)\n\(request.sentenceContext)"
    }

    private func displayText(from translatedText: String) -> String {
        let trimmedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine = trimmedText
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else {
            return ""
        }

        return firstLine
    }

    private func wordLookupFailure(
        from error: Error,
        providerID: TranslationProviderID
    ) -> WordLookupFailure {
        if let failure = error as? WordLookupFailure {
            return failure
        }
        if isCancellation(error) {
            return .cancelled
        }
        guard let translationFailure = error as? TranslationFailure else {
            return .providerFailed
        }

        switch translationFailure {
        case .captureCancelled:
            return .cancelled
        case let .missingAPIKey(providerID):
            return .missingAPIKey(providerID)
        case let .missingLanguagePack(providerID):
            return .missingLanguagePack(providerID)
        case let .providerUnavailable(providerID):
            return .providerUnavailable(providerID)
        case .unsupportedLanguagePair:
            return .unsupportedLanguagePair
        default:
            return .providerFailed
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

public struct UnavailableWordLookupProvider: WordLookupProviding {
    public init() {}

    public func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        throw WordLookupFailure.providerUnavailable(request.providerID)
    }
}

public protocol LanguageAvailabilityChecking: Sendable {
    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness
}

public protocol AppSettingsStoring: Sendable {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
}

public enum APIKeyStatus: Equatable, Sendable {
    case present
    case missing
    case unavailable(String)
}

public protocol APIKeyStoring: Sendable {
    func apiKey(for providerID: TranslationProviderID) async throws -> String?
    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws
    func deleteAPIKey(for providerID: TranslationProviderID) async throws
    func apiKeyStatus(for providerID: TranslationProviderID) async -> APIKeyStatus
    func apiRegion(for providerID: TranslationProviderID) async throws -> String?
    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws
    func deleteAPIRegion(for providerID: TranslationProviderID) async throws
}

public protocol LaunchAtLoginServicing: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ isEnabled: Bool) async throws
}

public protocol TranslationHistoryStoring: Sendable {
    func save(_ result: TranslationResult) async throws
    func recent(limit: Int) async throws -> [TranslationResult]
}

public protocol PermissionChecking: Sendable {
    func status(for kind: PermissionKind) async -> PermissionStatus
    func request(for kind: PermissionKind) async -> PermissionStatus
}

public protocol ClipboardServicing: Sendable {
    func readText() async -> String?
    func writeText(_ text: String) async
}

public protocol SelectedTextCapturing: Sendable {
    func captureSelectedText() async throws -> String
}

public protocol ShortcutRegistering: Sendable {
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws
    func unregister(_ action: ShortcutAction) async
}

public protocol ScreenTranslationSoundPlaying: Sendable {
    func availableSoundNames() async -> [String]
    func playSound(named soundName: String) async
}

public enum ScreenTranslationNotificationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable

    public var allowsPosting: Bool {
        switch self {
        case .authorized:
            true
        case .notDetermined, .denied, .unavailable:
            false
        }
    }
}

public protocol ScreenTranslationNotificationPosting: Sendable {
    func authorizationStatus() async -> ScreenTranslationNotificationStatus
    func requestAuthorization() async -> ScreenTranslationNotificationStatus
    func postScreenTranslation(result: TranslationResult) async
    func openNotificationSettings() async
}

public protocol CloudTranslationClient: Sendable {
    func perform(_ request: CloudTranslationHTTPRequest) async throws -> CloudTranslationHTTPResponse
}

public struct NoOpScreenTranslationSoundPlayer: ScreenTranslationSoundPlaying {
    public init() {}

    public func availableSoundNames() async -> [String] {
        []
    }

    public func playSound(named soundName: String) async {
        _ = soundName
    }
}

public struct NoOpScreenTranslationNotifier: ScreenTranslationNotificationPosting {
    public init() {}

    public func authorizationStatus() async -> ScreenTranslationNotificationStatus {
        .unavailable
    }

    public func requestAuthorization() async -> ScreenTranslationNotificationStatus {
        .unavailable
    }

    public func postScreenTranslation(result: TranslationResult) async {
        _ = result
    }

    public func openNotificationSettings() async {}
}
