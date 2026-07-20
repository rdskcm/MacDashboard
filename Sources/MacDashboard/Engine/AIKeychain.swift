// Engine/AIKeychain.swift
// Keychain wrapper for the AI API key (Block AI, Wave 2). Plain generic-password
// item — deliberately no kSecAttrAccessControl / access groups / data-protection
// keychain, since this app is ad-hoc signed and re-signed on every build, and a
// signature-bound ACL would break across rebuilds. Not symlinked into the Checks
// target (impure: talks to the real Keychain).
import Foundation
import Security

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
enum KeychainStore {
    static let service = "com.rdskcm.mac-dashboard.ai-api-key"
    static let account = "default"

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete() // ignore result: absence of a prior item is not an error here

        guard let data = key.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Presence check only — uses `kSecReturnAttributes`, never `kSecReturnData`,
    /// so it never decrypts the secret value and never triggers an unlock prompt.
    static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
#endif
