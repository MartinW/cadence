import Foundation
import Security

/// Thin Keychain wrapper for app credentials (Langfuse + OpenRouter keys).
///
/// We never write these to UserDefaults or any plain file — Keychain is the
/// only on-device store. The service identifier is the bundle id; account is
/// the variable name (e.g. "LANGFUSE_PUBLIC_KEY").
enum SecretsStore {
    private static let service = "dev.martinwright.cadence"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func write(_ key: String, value: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Idempotent: delete any prior entry, then add fresh.
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = value.data(using: .utf8) ?? Data()
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
