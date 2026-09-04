import Foundation
import Security

/// Where API keys live. Abstracted so the settings store can be unit-tested without touching
/// the real Keychain, which isn't available in the test host anyway.
protocol SecretStore {
    func read(account: String) -> String?
    func write(_ value: String, account: String)
    func delete(account: String)
}

/// Keychain-backed secrets, one generic-password item per account under a single service.
/// Same shape as `SpotifyTokenStore`, generalized.
struct KeychainSecretStore: SecretStore {
    let service: String

    func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        // Keys are only ever read by the app itself, in the foreground, after first unlock.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Test double. Also handy for previews.
final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func read(account: String) -> String? { values[account] }
    func write(_ value: String, account: String) { values[account] = value }
    func delete(account: String) { values[account] = nil }
}
