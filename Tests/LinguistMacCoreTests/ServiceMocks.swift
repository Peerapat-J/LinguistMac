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
    var requiresAPIKey: Bool
    var usesNetwork: Bool
    var translatedText: String
    var failure: TranslationFailure?

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
        [
            TranslationProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                requiresAPIKey: provider.requiresAPIKey,
                usesNetwork: provider.usesNetwork
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
