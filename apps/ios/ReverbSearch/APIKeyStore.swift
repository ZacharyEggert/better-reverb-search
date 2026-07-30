import Foundation
import Security

/// Optional personal API key. Search answers unauthenticated; a key just buys
/// rate-limit headroom. Keychain rather than UserDefaults — it's a bearer token.
enum APIKeyStore {
    private static let account = "reverb-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.betterreverbsearch.ios",
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        remove()
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
