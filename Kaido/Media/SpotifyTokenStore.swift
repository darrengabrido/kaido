import Foundation
import Security

/// Persists the Spotify App Remote access token in the Keychain so a killed-and-relaunched app
/// can reconnect without bouncing back to the Spotify app for a fresh OAuth grant every time.
///
/// App Remote's implicit `authorizeAndPlayURI` grant doesn't hand back an expiry, so this tracks
/// one itself using Spotify's documented ~1 hour access token lifetime, and treats a token past
/// that point as absent rather than let a caller retry a token that's certainly dead.
enum SpotifyTokenStore {
    private static let service = "com.oaktreehouse.kaido.spotify"
    private static let account = "app-remote-access-token"
    private static let expiryDefaultsKey = "SpotifyAccessTokenExpiry"
    private static let assumedLifetime: TimeInterval = 3600

    static func save(token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)

        UserDefaults.standard.set(Date().addingTimeInterval(assumedLifetime), forKey: expiryDefaultsKey)
    }

    /// The stored token, or `nil` if there is none or it's past its assumed expiry (clearing it
    /// in that case so a stale token can't linger and get reused).
    static func loadValidToken() -> String? {
        guard let expiry = UserDefaults.standard.object(forKey: expiryDefaultsKey) as? Date,
              expiry > Date() else {
            clear()
            return nil
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: expiryDefaultsKey)
    }
}
