import Foundation
import OSLog
import Security

enum Log {
    static let app = Logger(subsystem: "com.facemacos.app", category: "app")
    static let unlock = Logger(subsystem: "com.facemacos.app", category: "unlock")
}

enum Keychain {
    private static let service = "com.facemacos.app"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.app.error("Keychain read \(account, privacy: .public) failed: \(message(for: status), privacy: .public)")
        }
        return status == errSecSuccess ? result as? Data : nil
    }

    @discardableResult
    static func write(_ data: Data, account: String) -> OSStatus {
        let query = baseQuery(account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.app.error("Keychain write \(account, privacy: .public) failed: \(message(for: status), privacy: .public)")
        }
        return status
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    static func message(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}
