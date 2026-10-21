import Foundation
import Security

/// Persists the auth session between launches.
protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession) throws(AppError)
    func clear()
}

/// Stores the session as a single Keychain item, readable only on this device after first unlock
/// (so background refreshes work) and excluded from backups and device migration.
struct KeychainSessionStore: SessionStore {
    let service: String
    var account = "supabase-session"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Log.auth.error("Keychain read failed: \(status, privacy: .public)")
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            Log.auth.error("Stored session was unreadable and has been discarded")
            clear()
            return nil
        }
    }

    func save(_ session: AuthSession) throws(AppError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw .unexpected
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            Log.auth.error("Keychain write failed: \(status, privacy: .public)")
            throw .unexpected
        }
    }

    func clear() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.auth.error("Keychain delete failed: \(status, privacy: .public)")
        }
    }
}
