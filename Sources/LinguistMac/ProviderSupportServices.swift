import Foundation
import LinguistMacCore
import Security
import ServiceManagement

actor KeychainAPIKeyStore: APIKeyStoring {
    private let service = "\(AppIdentity.linguistMac.bundleIdentifier).provider-api-keys"

    func apiKey(for providerID: TranslationProviderID) async throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery(for: providerID) as CFDictionary, &item)

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

    func saveAPIKey(_ apiKey: String, for providerID: TranslationProviderID) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw KeychainAPIKeyStoreError.emptyKey
        }
        let data = Data(trimmedKey.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: providerID) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainAPIKeyStoreError.unhandledStatus(updateStatus)
        }

        var addQuery = baseQuery(for: providerID)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainAPIKeyStoreError.unhandledStatus(addStatus)
        }
    }

    func deleteAPIKey(for providerID: TranslationProviderID) async throws {
        let status = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAPIKeyStoreError.unhandledStatus(status)
        }
    }

    func containsAPIKey(for providerID: TranslationProviderID) async -> Bool {
        await (try? apiKey(for: providerID))?.isEmpty == false
    }

    private func baseQuery(for providerID: TranslationProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.rawValue
        ]
    }

    private func readQuery(for providerID: TranslationProviderID) -> [String: Any] {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
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
    func perform(_ request: CloudTranslationHTTPRequest) async throws -> CloudTranslationHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
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
