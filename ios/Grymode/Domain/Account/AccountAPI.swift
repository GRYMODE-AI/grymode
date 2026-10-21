import Foundation

/// The signed-in user's profile as stored by the Grymode API.
struct RemoteProfile: Decodable, Equatable, Sendable {
    let id: UUID
    let email: String?
    let displayName: String?
    let styleProfile: StyleProfile
    let onboardingCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct AccountDeletionResult: Decodable, Equatable, Sendable {
    let status: String
    let requestId: UUID
    let subscriptionNotice: String
}

enum AccountAPI {
    static func me() -> Endpoint<RemoteProfile> {
        Endpoint(method: .get, path: "/v1/me")
    }

    static func updateStyleProfile(
        _ profile: StyleProfile,
        onboardingCompleted: Bool
    ) throws(AppError) -> Endpoint<RemoteProfile> {
        let body = try JSONCoding.encode(
            UpdateStyleProfileBody(styleProfile: profile, onboardingCompleted: onboardingCompleted)
        )
        return Endpoint(method: .put, path: "/v1/me/style-profile", body: body)
    }

    /// Idempotent on the server, so the standard retry policy for DELETE is safe.
    static func deleteAccount() -> Endpoint<AccountDeletionResult> {
        Endpoint(method: .delete, path: "/v1/me", timeout: 60)
    }
}

private struct UpdateStyleProfileBody: Encodable {
    let styleProfile: StyleProfile
    let onboardingCompleted: Bool
}
