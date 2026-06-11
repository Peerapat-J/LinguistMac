import Foundation
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
    var failure: TranslationFailure?

    func isConfigured() async -> Bool {
        failure != .missingAPIKey(id)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        if let failure {
            throw failure
        }

        return TranslationResult(
            request: request,
            translatedText: translatedText
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
        await [
            TranslationProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                requiresAPIKey: provider.requiresAPIKey,
                usesNetwork: provider.usesNetwork,
                detail: provider.detail,
                configurationStatus: provider.isConfigured() ? .ready : .needsAPIKey,
                privacySummary: provider.privacySummary
            )
        ]
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

    init(keys: [TranslationProviderID: String] = [:]) {
        self.keys = keys
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

    func containsAPIKey(for providerID: TranslationProviderID) async -> Bool {
        keys[providerID]?.isEmpty == false
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

    init(results: [TranslationResult] = []) {
        self.results = results
    }

    func save(_ result: TranslationResult) async throws {
        results.insert(result, at: 0)
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        Array(results.prefix(limit))
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
