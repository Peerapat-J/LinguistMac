@testable import LinguistMacCore

struct StubScreenCaptureService: ScreenCaptureServicing {
    var result: Result<CapturedScreenRegion, TranslationFailure>

    func captureSelection() async throws -> CapturedScreenRegion {
        try result.get()
    }
}

struct StubOCRService: OCRServicing {
    var result: Result<RecognizedText, TranslationFailure>

    func recognizeText(in region: CapturedScreenRegion) async throws -> RecognizedText {
        _ = region
        return try result.get()
    }
}

struct StubTranslationProvider: TranslationProviding {
    var id: TranslationProviderID
    var displayName: String
    var detail: String = "Stub provider"
    var requiresAPIKey: Bool
    var usesNetwork: Bool
    var privacySummary: String = "Stub privacy"
    var translatedText: String
    var translatedTextsBySource: [String: String] = [:]
    var failure: TranslationFailure?

    func configurationStatus() async -> TranslationProviderConfigurationStatus {
        switch failure {
        case let .missingAPIKey(providerID) where providerID == id:
            .needsAPIKey
        case let .providerUnavailable(providerID) where providerID == id:
            .unavailable("Unavailable")
        default:
            .ready
        }
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        if let failure {
            throw failure
        }

        return TranslationResult(
            request: request,
            translatedText: translatedTextsBySource[request.text] ?? translatedText
        )
    }
}

struct StubTranslationProviderRegistry: TranslationProviderRegistry {
    var provider: StubTranslationProvider

    func provider(for id: TranslationProviderID) async throws -> any TranslationProviding {
        guard id == provider.id else {
            throw TranslationFailure.providerUnavailable(id)
        }

        return provider
    }

    func availableProviders() async -> [TranslationProviderDescriptor] {
        let status = await provider.configurationStatus()
        return [
            TranslationProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                requiresAPIKey: provider.requiresAPIKey,
                usesNetwork: provider.usesNetwork,
                detail: provider.detail,
                configurationStatus: status,
                privacySummary: provider.privacySummary
            )
        ]
    }
}

struct StubWordLookupProvider: WordLookupProviding {
    var result: Result<WordLookupResult?, WordLookupFailure>

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        _ = request
        return try result.get()
    }
}

struct StubLanguageAvailabilityChecker: LanguageAvailabilityChecking {
    var readiness: LanguagePackReadiness

    func readiness(
        from source: TranslationLanguage,
        to target: TranslationLanguage,
        sampleText: String?
    ) async -> LanguagePackReadiness {
        _ = source
        _ = target
        _ = sampleText
        return readiness
    }
}

actor InMemoryAppSettingsStore: AppSettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    func loadSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}

actor InMemoryAPIKeyStore: APIKeyStoring {
    private var keys: [TranslationProviderID: String]
    private var regions: [TranslationProviderID: String]

    init(keys: [TranslationProviderID: String] = [:], regions: [TranslationProviderID: String] = [:]) {
        self.keys = keys
        self.regions = regions
    }

    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        keys[providerID]
    }

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        keys[providerID] = apiKey
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        keys.removeValue(forKey: providerID)
    }

    func apiKeyStatus(for providerID: TranslationProviderID) async -> APIKeyStatus {
        keys[providerID]?.isEmpty == false ? .present : .missing
    }

    func apiRegion(for providerID: TranslationProviderID) async throws -> String? {
        regions[providerID]
    }

    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws {
        regions[providerID] = apiRegion
    }

    func deleteAPIRegion(for providerID: TranslationProviderID) async throws {
        regions.removeValue(forKey: providerID)
    }
}

actor StubLaunchAtLoginService: LaunchAtLoginServicing {
    private var enabled: Bool

    init(enabled: Bool = false) {
        self.enabled = enabled
    }

    func isEnabled() async -> Bool {
        enabled
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        enabled = isEnabled
    }
}

actor InMemoryTranslationHistoryStore: TranslationHistoryStoring {
    private var results: [TranslationResult]
    private let limit: Int

    init(
        results: [TranslationResult] = [],
        limit: Int = TranslationHistoryPolicy.defaultLimit
    ) {
        self.results = results
        self.limit = limit
    }

    func save(_ result: TranslationResult) async throws {
        results = TranslationHistoryPolicy.inserting(result, into: results, limit: limit)
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        TranslationHistoryPolicy.trimmed(results, limit: limit)
    }
}

struct FailingTranslationHistoryStore: TranslationHistoryStoring {
    func save(_ result: TranslationResult) async throws {
        _ = result
        throw TranslationFailure.providerFailed("History save failed.")
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        _ = limit
        throw TranslationFailure.providerFailed("History load failed.")
    }
}

struct StubPermissionChecker: PermissionChecking {
    var statuses: [PermissionKind: PermissionStatus]
    var requestStatuses: [PermissionKind: PermissionStatus] = [:]

    func status(for kind: PermissionKind) async -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    func request(for kind: PermissionKind) async -> PermissionStatus {
        requestStatuses[kind] ?? statuses[kind] ?? .notDetermined
    }
}

actor InMemoryClipboard: ClipboardServicing {
    private var text: String?

    init(text: String? = nil) {
        self.text = text
    }

    func readText() async -> String? {
        text
    }

    func writeText(_ text: String) async {
        self.text = text
    }
}

struct StubSelectedTextCapture: SelectedTextCapturing {
    var result: Result<String, TranslationFailure>

    func captureSelectedText() async throws -> String {
        try result.get()
    }
}

actor RecordingShortcutRegistry: ShortcutRegistering {
    private var registrations: [ShortcutAction: KeyboardShortcut] = [:]

    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async throws {
        registrations[action] = shortcut
    }

    func unregister(_ action: ShortcutAction) async {
        registrations.removeValue(forKey: action)
    }

    func registeredShortcut(for action: ShortcutAction) async -> KeyboardShortcut? {
        registrations[action]
    }
}

actor StubCloudTranslationClient: CloudTranslationClient {
    private(set) var requests: [CloudTranslationHTTPRequest] = []
    var response: CloudTranslationHTTPResponse

    init(response: CloudTranslationHTTPResponse) {
        self.response = response
    }

    func perform(_ request: CloudTranslationHTTPRequest) async throws -> CloudTranslationHTTPResponse {
        requests.append(request)
        return response
    }
}
