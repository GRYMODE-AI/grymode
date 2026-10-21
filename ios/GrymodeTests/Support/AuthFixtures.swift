import Foundation
import XCTest

@testable import Grymode

enum AuthFixtures {
    static let userID = UUID(uuidString: "6F1C3E9A-0000-4000-8000-000000000001") ?? UUID()
    static let email = "ada@example.com"
    static let supabaseURL = URL(string: "http://127.0.0.1:54321") ?? URL(fileURLWithPath: "/")
    static let apiURL = URL(string: "http://127.0.0.1:8000") ?? URL(fileURLWithPath: "/")
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func session(access: String = "access-1", refresh: String = "refresh-1", expiresIn: TimeInterval = 3600)
        -> AuthSession
    {
        AuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(expiresIn),
            user: AuthUser(id: userID, email: email)
        )
    }

    static func tokenBody(access: String, refresh: String, expiresIn: Int = 3600) -> Data {
        json([
            "access_token": access,
            "token_type": "bearer",
            "expires_in": expiresIn,
            "expires_at": Int(now.timeIntervalSince1970) + expiresIn,
            "refresh_token": refresh,
            "user": ["id": userID.uuidString.lowercased(), "email": email, "aud": "authenticated"],
        ])
    }

    static func authError(
        _ errorCode: String, status: Int, message: String = "Supabase wording that must not reach users"
    ) -> Data {
        json(["code": status, "error_code": errorCode, "msg": message])
    }

    /// Supabase's response when a code was already sent to the address within the last minute.
    static let codeRecentlySentError = authError(
        "over_email_send_rate_limit", status: 429,
        message: "For security purposes, you can only request this after 42 seconds.")

    static func profileBody(style: [String: Any] = [:], onboardingCompleted: Bool) -> Data {
        json([
            "id": userID.uuidString.lowercased(),
            "email": email,
            "display_name": NSNull(),
            "style_profile": ["axes": [:], "occasions": [], "palettes": []].merging(style) { $1 },
            "onboarding_completed_at": onboardingCompleted ? "2026-10-10T10:00:00.123456Z" : NSNull(),
            "created_at": "2026-10-10T09:00:00.000001Z",
            "updated_at": "2026-10-10T10:00:00Z",
        ])
    }

    static func deletionBody() -> Data {
        json([
            "status": "completed",
            "request_id": "0b7d1c1e-4a3b-4b5e-9a51-6a7c1d2e3f40",
            "subscription_notice": "Deleting your account does not cancel an App Store subscription.",
        ])
    }

    static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func makeClient(_ transport: StubTransport) -> SupabaseAuthClient {
        SupabaseAuthClient(
            baseURL: supabaseURL,
            publishableKey: "sb_publishable_test",
            transport: transport,
            now: { now }
        )
    }

    static func makeAuthService(
        _ transport: StubTransport,
        store: EphemeralSessionStore = EphemeralSessionStore()
    ) -> AuthService {
        AuthService(client: makeClient(transport), store: store, now: { now })
    }

    static func makeAPIClient(_ transport: StubTransport, tokens: any AccessTokenProviding) -> APIClient {
        APIClient(
            builder: RequestBuilder(baseURL: apiURL, clientVersion: "test"),
            transport: transport,
            tokens: tokens,
            sleep: { _ in }
        )
    }
}

extension URLRequest {
    /// The JSON body decoded as a dictionary, for asserting on what was sent.
    func jsonBody(file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let data = try XCTUnwrap(httpBody, "request has no body", file: file, line: line)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
    }
}
