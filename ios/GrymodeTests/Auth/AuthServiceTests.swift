import XCTest

@testable import Grymode

final class AuthServiceTests: XCTestCase {
    func testRestoresTheSavedSession() async {
        let store = EphemeralSessionStore(session: AuthFixtures.session())
        let service = AuthFixtures.makeAuthService(StubTransport([]), store: store)

        let user = await service.restoreSession()

        XCTAssertEqual(user?.id, AuthFixtures.userID)
    }

    func testFreshTokensAreUsedWithoutTouchingTheNetwork() async {
        let transport = StubTransport([])
        let service = AuthFixtures.makeAuthService(
            transport, store: EphemeralSessionStore(session: AuthFixtures.session()))
        _ = await service.restoreSession()

        let token = await service.currentAccessToken()

        XCTAssertEqual(token, "access-1")
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testExpiringTokensAreRefreshedAndSaved() async {
        let store = EphemeralSessionStore(session: AuthFixtures.session(expiresIn: 30))
        let transport = StubTransport([
            .response(status: 200, body: AuthFixtures.tokenBody(access: "a2", refresh: "r2"))
        ])
        let service = AuthFixtures.makeAuthService(transport, store: store)
        _ = await service.restoreSession()

        let token = await service.currentAccessToken()

        XCTAssertEqual(token, "a2")
        XCTAssertEqual(store.load()?.refreshToken, "r2")
    }

    func testConcurrentCallersShareOneRefresh() async {
        let transport = StubTransport([
            .response(status: 200, body: AuthFixtures.tokenBody(access: "a2", refresh: "r2"))
        ])
        let service = AuthFixtures.makeAuthService(
            transport, store: EphemeralSessionStore(session: AuthFixtures.session(expiresIn: 0)))
        _ = await service.restoreSession()

        async let first = service.refreshAccessToken()
        async let second = service.currentAccessToken()
        let tokens = await [first, second]

        XCTAssertEqual(tokens, ["a2", "a2"])
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testRejectedRefreshEndsTheSessionAndNotifies() async {
        let store = EphemeralSessionStore(session: AuthFixtures.session(expiresIn: 0))
        let transport = StubTransport([
            .response(status: 400, body: AuthFixtures.authError("refresh_token_already_used", status: 400))
        ])
        let service = AuthFixtures.makeAuthService(transport, store: store)
        _ = await service.restoreSession()
        let changes = await service.userChanges()

        let token = await service.refreshAccessToken()

        XCTAssertNil(token)
        XCTAssertNil(store.load())
        let currentUser = await service.currentUser
        XCTAssertNil(currentUser)
        var iterator = changes.makeAsyncIterator()
        let change = await iterator.next()
        XCTAssertEqual(change, .some(nil))
    }

    func testTransientRefreshFailureKeepsTheSession() async {
        let store = EphemeralSessionStore(session: AuthFixtures.session(expiresIn: 0))
        let service = AuthFixtures.makeAuthService(StubTransport([.failure(.notConnectedToInternet)]), store: store)
        _ = await service.restoreSession()

        let token = await service.currentAccessToken()

        XCTAssertEqual(token, "access-1", "An offline refresh should let the request fail as offline, not sign out")
        XCTAssertNotNil(store.load())
    }

    func testVerifyingACodeSignsInAndSaves() async throws {
        let store = EphemeralSessionStore()
        let transport = StubTransport([.response(status: 200, body: AuthFixtures.tokenBody(access: "a", refresh: "r"))])
        let service = AuthFixtures.makeAuthService(transport, store: store)

        let user = try await service.verify(code: "123456", email: AuthFixtures.email)

        XCTAssertEqual(user.email, AuthFixtures.email)
        XCTAssertEqual(store.load()?.accessToken, "a")
        let token = await service.currentAccessToken()
        XCTAssertEqual(token, "a")
    }

    func testSignOutClearsLocallyEvenWhenTheServerIsUnreachable() async {
        let store = EphemeralSessionStore(session: AuthFixtures.session())
        let service = AuthFixtures.makeAuthService(StubTransport([.failure(.timedOut)]), store: store)
        _ = await service.restoreSession()

        await service.signOut()

        XCTAssertNil(store.load())
        let token = await service.currentAccessToken()
        XCTAssertNil(token)
    }
}
