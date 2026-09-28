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

    /// `allowPrompt: false` fails instead of showing a Keychain access dialog (e.g. behind the lock screen,
    /// where nobody could answer it and the read would hang).
    static func read(_ account: String, allowPrompt: Bool = true) -> Data? {
        let (data, status) = readWithStatus(account, allowPrompt: allowPrompt)
        return status == errSecSuccess ? data : nil
    }

    static func readWithStatus(_ account: String, allowPrompt: Bool = true) -> (Data?, OSStatus) {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowPrompt { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.app.error("Keychain read \(account, privacy: .public) failed: \(message(for: status), privacy: .public)")
        }
        return (result as? Data, status)
    }

    /// Checks for an item without reading its secret, so it never triggers a Keychain access prompt.
    static func exists(_ account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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

/// All FaceMacOS secrets (face data, login password, vault note) in a single Keychain item.
///
/// Without an Apple Developer Team ID, macOS ties "Always Allow" to one exact build, so each update asks again.
/// Keeping everything in one item means at most one prompt per update instead of one per secret.
enum Secrets {
    struct Payload: Codable {
        var faceTemplate: Data?
        var loginPassword: String?
        var vaultNote: String?
    }

    private static let account = "secrets"
    private static let legacyAccounts = (face: "face-template", password: "login-password", vault: "vault-note")
    /// Whether a login password is saved, remembered after the first read so UI checks never prompt.
    private static var knownHasPassword: Bool?

    static var hasLoginPassword: Bool {
        if let known = knownHasPassword { return known }
        return load()?.loginPassword != nil
    }

    /// Returns nil if the item can't be read (for example access was denied); an empty payload if nothing is saved.
    static func load(allowPrompt: Bool = true) -> Payload? {
        let (data, status) = Keychain.readWithStatus(account, allowPrompt: allowPrompt)
        switch status {
        case errSecSuccess:
            guard let data, let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
            knownHasPassword = payload.loginPassword != nil
            return payload
        case errSecItemNotFound:
            return allowPrompt ? migrateLegacyItems() : nil
        default:
            return nil
        }
    }

    /// Applies a change and saves. Does nothing if the existing item can't be read, so it's never overwritten.
    @discardableResult
    static func update(_ change: (inout Payload) -> Void) -> OSStatus {
        guard var payload = load() else { return errSecInteractionNotAllowed }
        change(&payload)
        return save(payload)
    }

    static func deleteAll() {
        Keychain.delete(account)
        [legacyAccounts.face, legacyAccounts.password, legacyAccounts.vault].forEach(Keychain.delete)
        knownHasPassword = false
    }

    private static func save(_ payload: Payload) -> OSStatus {
        guard let data = try? JSONEncoder().encode(payload) else { return errSecParam }
        let status = Keychain.write(data, account: account)
        if status == errSecSuccess { knownHasPassword = payload.loginPassword != nil }
        return status
    }

    /// One-time move from the older one-item-per-secret layout. macOS asks once for each old item here.
    private static func migrateLegacyItems() -> Payload {
        let legacy = [legacyAccounts.face, legacyAccounts.password, legacyAccounts.vault]
        guard legacy.contains(where: Keychain.exists) else {
            knownHasPassword = false
            return Payload()
        }
        let payload = Payload(
            faceTemplate: Keychain.read(legacyAccounts.face),
            loginPassword: Keychain.read(legacyAccounts.password).flatMap { String(data: $0, encoding: .utf8) },
            vaultNote: Keychain.read(legacyAccounts.vault).flatMap { String(data: $0, encoding: .utf8) }
        )
        if save(payload) == errSecSuccess {
            legacy.forEach(Keychain.delete)
            Log.app.notice("Moved secrets into a single Keychain item")
        }
        return payload
    }
}
