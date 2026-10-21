import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let id: UUID
    let email: String?
}

/// A Supabase Auth session. Stored only in the Keychain; never logged.
struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    /// True when the access token expires within `leeway` seconds and should be refreshed first.
    func needsRefresh(now: Date, leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}
