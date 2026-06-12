import Foundation
import LinguistMacCore
import Security
import ServiceManagement

actor KeychainAPIKeyStore: APIKeyStoring {
    private let service = "\(AppIdentity.linguistMac.bundleIdentifier).provider-api-keys"

    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        try credential(for: providerID, field: .apiKey)
    }

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        try saveCredential(apiKey, for: providerID, field: .apiKey)
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        try deleteCredential(for: providerID, field: .apiKey)
    }

    func containsAPIKey(for providerID: TranslationProviderID) async -> Bool {
        await (try? apiKey(for: providerID))?.isEmpty == false
    }

    func apiRegion(for providerID: TranslationProviderID) async throws -> String? {
        try credential(for: providerID, field: .apiRegion)
    }

    func saveAPIRegion(_ apiRegion: String, for providerID: TranslationProviderID) async throws {
        try saveCredential(apiRegion, for: providerID, field: .apiRegion)
    }

    func deleteAPIRegion(for providerID: TranslationProviderID) async throws {
        try deleteCredential(for: providerID, field: .apiRegion)
    }

    private func credential(
        for providerID: TranslationProviderID,
        field: KeychainAPIKeyStoreCredentialField
    ) throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery(for: providerID, field: field) as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainAPIKeyStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            throw KeychainAPIKeyStoreError.invalidStoredValue
        }

        return key
    }

    private func saveCredential(
        _ value: String,
        for providerID: TranslationProviderID,
        field: KeychainAPIKeyStoreCredentialField
    ) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw KeychainAPIKeyStoreError.emptyKey
        }
        let data = Data(trimmedValue.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: providerID, field: field) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainAPIKeyStoreError.unhandledStatus(updateStatus)
        }

        var addQuery = baseQuery(for: providerID, field: field)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainAPIKeyStoreError.unhandledStatus(addStatus)
        }
    }

    private func deleteCredential(
        for providerID: TranslationProviderID,
        field: KeychainAPIKeyStoreCredentialField
    ) throws {
        let status = SecItemDelete(baseQuery(for: providerID, field: field) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAPIKeyStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(
        for providerID: TranslationProviderID,
        field: KeychainAPIKeyStoreCredentialField
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.accountName(for: providerID)
        ]
    }

    private func readQuery(
        for providerID: TranslationProviderID,
        field: KeychainAPIKeyStoreCredentialField
    ) -> [String: Any] {
        var query = baseQuery(for: providerID, field: field)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}

private enum KeychainAPIKeyStoreCredentialField {
    case apiKey
    case apiRegion

    func accountName(for providerID: TranslationProviderID) -> String {
        switch self {
        case .apiKey:
            providerID.rawValue
        case .apiRegion:
            "\(providerID.rawValue).region"
        }
    }
}

private enum KeychainAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredValue
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "API key cannot be empty."
        case .invalidStoredValue:
            "The stored API key could not be read."
        case let .unhandledStatus(status):
            "Keychain request failed (\(status))."
        }
    }
}

struct URLSessionCloudTranslationClient: CloudTranslationClient {
    private let session: URLSession

    init(session: URLSession = URLSessionCloudTranslationClient.makeEphemeralSession()) {
        self.session = session
    }

    func perform(_ request: CloudTranslationHTTPRequest) async throws -> CloudTranslationHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationFailure.providerFailed("Provider returned an invalid response.")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw TranslationFailure.providerFailed(
                "\(request.providerID.rawValue) request failed with HTTP \(httpResponse.statusCode)."
            )
        }

        return CloudTranslationHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }
}

actor SystemLaunchAtLoginService: LaunchAtLoginServicing {
    func isEnabled() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        let service = SMAppService.mainApp
        if isEnabled {
            guard service.status != .enabled else {
                return
            }
            try service.register()
        } else {
            guard service.status == .enabled else {
                return
            }
            try await service.unregister()
        }
    }
}
