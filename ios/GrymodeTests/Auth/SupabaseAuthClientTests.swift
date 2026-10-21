import XCTest

@testable import Grymode

final class SupabaseAuthClientTests: XCTestCase {
    func testSendCodeRequestsAnEmailOTPWithThePublishableKey() async throws {
        let transport = StubTransport([.response(status: 200, body: Data("{}".utf8))])

        try await AuthFixtures.makeClient(transport).sendEmailCode(to: "ada@example.com")

        let request = try await unwrapAsync(await transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:54321/auth/v1/otp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try request.jsonBody()
        XCTAssertEqual(body["email"] as? String, "ada@example.com")
        XCTAssertEqual(body["create_user"] as? Bool, true)
    }

    func testVerifyReturnsASessionThatExpiresRelativeToNow() async throws {
        let transport = StubTransport([
            .response(status: 200, body: AuthFixtures.tokenBody(access: "a", refresh: "r", expiresIn: 3600))
        ])

        let session = try await AuthFixtures.makeClient(transport).verifyEmailCode("123456", email: "ada@example.com")

        XCTAssertEqual(session.accessToken, "a")
        XCTAssertEqual(session.refreshToken, "r")
        XCTAssertEqual(session.expiresAt, AuthFixtures.now.addingTimeInterval(3600))
        XCTAssertEqual(session.user, AuthUser(id: AuthFixtures.userID, email: AuthFixtures.email))
        let body = try await unwrapAsync(await transport.requests.first).jsonBody()
        XCTAssertEqual(body["type"] as? String, "email")
        XCTAssertEqual(body["token"] as? String, "123456")
    }

    func testRefreshUsesTheRefreshTokenGrant() async throws {
        let transport = StubTransport([
            .response(status: 200, body: AuthFixtures.tokenBody(access: "a2", refresh: "r2"))
        ])

        let session = try await AuthFixtures.makeClient(transport).refresh(refreshToken: "r1")

        XCTAssertEqual(session.accessToken, "a2")
        let request = try await unwrapAsync(await transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:54321/auth/v1/token?grant_type=refresh_token")
        XCTAssertEqual(try request.jsonBody()["refresh_token"] as? String, "r1")
    }

    func testRejectedRefreshMeansSignedOut() async {
        let transport = StubTransport([
            .response(status: 400, body: AuthFixtures.authError("refresh_token_not_found", status: 400))
        ])

        let error = await capturedError { try await AuthFixtures.makeClient(transport).refresh(refreshToken: "gone") }

        XCTAssertEqual(error, .unauthorized(requestID: nil))
    }

    func testWrongOrExpiredCodeHasFriendlyWording() async {
        let transport = StubTransport([.response(status: 403, body: AuthFixtures.authError("otp_expired", status: 403))]
        )

        let error = await capturedError {
            try await AuthFixtures.makeClient(transport).verifyEmailCode("000000", email: "ada@example.com")
        }

        XCTAssertEqual(error?.apiCode, "invalid_code")
        XCTAssertEqual(error?.isRetryable, false)
        XCTAssertFalse(error?.userMessage.contains("Supabase") ?? true)
    }

    func testRateLimitsAreRetryable() async {
        let transport = StubTransport([
            .response(status: 429, body: AuthFixtures.authError("over_email_send_rate_limit", status: 429))
        ])

        let error = await capturedError { try await AuthFixtures.makeClient(transport).sendEmailCode(to: "a@b.co") }

        XCTAssertEqual(error?.apiCode, "rate_limited")
        XCTAssertEqual(error?.isRetryable, true)
    }

    func testPerAddressThrottleMeansACodeWasAlreadySent() async {
        let transport = StubTransport([.response(status: 429, body: AuthFixtures.codeRecentlySentError)])

        let error = await capturedError { try await AuthFixtures.makeClient(transport).sendEmailCode(to: "a@b.co") }

        XCTAssertEqual(error?.apiCode, AuthErrorMapper.codeRecentlySent)
        XCTAssertFalse(error?.userMessage.contains("security purposes") ?? true)
        XCTAssertEqual(AuthErrorMapper.retryAfterSeconds(in: AuthFixtures.codeRecentlySentError), 42)
    }

    func testServerErrorsAndNonJSONBodiesAreHandled() async {
        let transport = StubTransport([.response(status: 502, body: Data("<html>Bad gateway</html>".utf8))])

        let error = await capturedError { try await AuthFixtures.makeClient(transport).sendEmailCode(to: "a@b.co") }

        XCTAssertEqual(error?.apiCode, "auth_unavailable")
        XCTAssertEqual(error?.isRetryable, true)
    }

    func testOfflineIsReportedAsOffline() async {
        let transport = StubTransport([.failure(.notConnectedToInternet)])

        let error = await capturedError { try await AuthFixtures.makeClient(transport).sendEmailCode(to: "a@b.co") }

        XCTAssertEqual(error, .offline)
    }

    func testSignOutRevokesOnlyThisDevice() async throws {
        let transport = StubTransport([.response(status: 204)])

        try await AuthFixtures.makeClient(transport).signOut(accessToken: "access-1")

        let request = try await unwrapAsync(await transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:54321/auth/v1/logout?scope=local")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
    }
}
