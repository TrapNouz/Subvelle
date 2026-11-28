import Foundation
import Security

/// Stores the safety copy of the subscriptions in the keychain. Keychain items survive the app's
/// files being cleared, and stay on this device (never synced).
enum SafetyKeychain {
    private static let service = "app.subspace.ios.safety-copy"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, account: String) {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query(account).merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func delete(account: String) { SecItemDelete(query(account) as CFDictionary) }
}
