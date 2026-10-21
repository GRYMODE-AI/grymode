import XCTest

@testable import Grymode

@MainActor
final class SignInModelTests: XCTestCase {
    private final class Clock {
        var now = AuthFixtures.now
    }

    private func makeModel(_ outcomes: [StubTransport.Outcome]) throws -> (SignInModel, StubTransport, Clock) {
        let transport = StubTransport(outcomes)
        let styleProfiles = StyleProfileStore(defaults: try makeEphemeralDefaults())
        let account = AccountModel(
            auth: AuthFixtures.makeAuthService(transport), api: nil, styleProfiles: styleProfiles)
        let clock = Clock()
        return (SignInModel(account: account, now: { clock.now }), transport, clock)
    }

    func testCodeAcceptsOnlySixDigits() throws {
        let (model, _, _) = try makeModel([])

        model.code = "12a3 45-678"

        XCTAssertEqual(model.code, "123456")
    }

    func testEmailPlausibility() {
        for valid in ["ada@example.com", "a.b+c@sub.example.co.uk"] {
            XCTAssertTrue(SignInModel.isPlausibleEmail(valid), valid)
        }
        for invalid in [
            "", "ada", "ada@", "@example.com", "ada@example", "ada@.com", "ada@example.", "a b@c.de", "a@b@c.de",
        ] {
            XCTAssertFalse(SignInModel.isPlausibleEmail(invalid), invalid)
        }
    }

    func testSendingNormalisesTheEmailAndStartsTheResendTimer() async throws {
        let (model, transport, clock) = try makeModel([.response(status: 200, body: Data("{}".utf8))])
        model.email = "  Ada@Example.com "

        let sent = await model.sendCode()

        XCTAssertTrue(sent)
        XCTAssertEqual(model.sentTo, "ada@example.com")
        XCTAssertEqual(model.secondsUntilResend(at: clock.now), 60)
        XCTAssertEqual(model.secondsUntilResend(at: clock.now.addingTimeInterval(61)), 0)
        let request = await transport.requests.first
        XCTAssertEqual(try XCTUnwrap(request).jsonBody()["email"] as? String, "ada@example.com")
    }

    func testReturningToTheSameEmailWithinTheWindowDoesNotSendAgain() async throws {
        let (model, transport, clock) = try makeModel([.response(status: 200, body: Data("{}".utf8))])
        model.email = "ada@example.com"
        _ = await model.sendCode()
        clock.now = clock.now.addingTimeInterval(10)

        let sentAgain = await model.sendCode()

        XCTAssertTrue(sentAgain)
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testResendIsBlockedDuringTheWindow() async throws {
        let (model, transport, clock) = try makeModel([
            .response(status: 200, body: Data("{}".utf8)), .response(status: 200, body: Data("{}".utf8)),
        ])
        model.email = "ada@example.com"
        _ = await model.sendCode()

        await model.resendCode()
        var requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)

        clock.now = clock.now.addingTimeInterval(60)
        await model.resendCode()
        requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 2)
    }

    func testACodeSentMomentsAgoIsUsedInsteadOfFailing() async throws {
        let (model, _, clock) = try makeModel([.response(status: 429, body: AuthFixtures.codeRecentlySentError)])
        model.email = "ada@example.com"

        let sent = await model.sendCode()

        XCTAssertTrue(sent)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.isUsingEarlierCode)
        XCTAssertEqual(model.sentTo, "ada@example.com")
        XCTAssertEqual(model.secondsUntilResend(at: clock.now), 60)
    }

    func testOtherRateLimitsStillShowAnError() async throws {
        let (model, _, _) = try makeModel([
            .response(
                status: 429,
                body: AuthFixtures.authError(
                    "over_email_send_rate_limit", status: 429, message: "email rate limit exceeded"))
        ])
        model.email = "ada@example.com"

        let sent = await model.sendCode()

        XCTAssertFalse(sent)
        XCTAssertEqual(model.error?.apiCode, "rate_limited")
        XCTAssertNil(model.sentTo)
    }

    func testWrongCodeShowsAnErrorAndStaysSignedOut() async throws {
        let (model, _, _) = try makeModel([
            .response(status: 200, body: Data("{}".utf8)),
            .response(status: 403, body: AuthFixtures.authError("otp_expired", status: 403)),
        ])
        model.email = "ada@example.com"
        _ = await model.sendCode()
        model.code = "000000"

        let verified = await model.verify()

        XCTAssertFalse(verified)
        XCTAssertEqual(model.error?.apiCode, "invalid_code")
        XCTAssertFalse(model.isWorking)
    }

    func testCorrectCodeSignsIn() async throws {
        let (model, _, _) = try makeModel([
            .response(status: 200, body: Data("{}".utf8)),
            .response(status: 200, body: AuthFixtures.tokenBody(access: "a", refresh: "r")),
        ])
        model.email = "ada@example.com"
        _ = await model.sendCode()
        model.code = "123456"

        let verified = await model.verify()

        XCTAssertTrue(verified)
        XCTAssertNil(model.error)
    }
}
