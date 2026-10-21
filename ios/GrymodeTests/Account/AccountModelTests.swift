import XCTest

@testable import Grymode

@MainActor
final class AccountModelTests: XCTestCase {
    private struct Harness {
        let model: AccountModel
        let styleProfiles: StyleProfileStore
        let sessions: EphemeralSessionStore
        let authTransport: StubTransport
        let apiTransport: StubTransport
    }

    private func makeHarness(
        signedIn: Bool,
        auth: [StubTransport.Outcome] = [],
        api: [StubTransport.Outcome] = []
    ) throws -> Harness {
        let sessions = EphemeralSessionStore(session: signedIn ? AuthFixtures.session() : nil)
        let authTransport = StubTransport(auth)
        let apiTransport = StubTransport(api)
        let service = AuthFixtures.makeAuthService(authTransport, store: sessions)
        let styleProfiles = StyleProfileStore(defaults: try makeEphemeralDefaults())
        let model = AccountModel(
            auth: service,
            api: AuthFixtures.makeAPIClient(apiTransport, tokens: service),
            styleProfiles: styleProfiles
        )
        return Harness(
            model: model, styleProfiles: styleProfiles, sessions: sessions, authTransport: authTransport,
            apiTransport: apiTransport)
    }

    private var chosenStyle: StyleProfile {
        var profile = StyleProfile.empty
        profile.toggle(.first, on: .silhouette)
        profile.toggle(Occasion.work)
        return profile
    }

    func testStartsSignedOutWithoutASavedSessionAndKeepsNoPreferences() async throws {
        let harness = try makeHarness(signedIn: false)
        harness.styleProfiles.completeOnboarding(with: chosenStyle)

        await harness.model.start()

        XCTAssertEqual(harness.model.state, .signedOut)
        XCTAssertFalse(harness.styleProfiles.hasCompletedOnboarding)
        XCTAssertEqual(harness.styleProfiles.profile, .empty)
    }

    func testRestoresASavedSession() async throws {
        let harness = try makeHarness(signedIn: true)

        await harness.model.start()

        XCTAssertEqual(harness.model.user?.id, AuthFixtures.userID)
    }

    func testFinishingSignInUploadsTheChosenStyle() async throws {
        let saved = AuthFixtures.profileBody(
            style: ["axes": ["silhouette": "first"], "occasions": ["work"]], onboardingCompleted: true)
        let harness = try makeHarness(
            signedIn: true,
            api: [
                .response(status: 200, body: AuthFixtures.profileBody(onboardingCompleted: false)),
                .response(status: 200, body: saved),
            ])
        await harness.model.start()

        let outcome = try await harness.model.finishSignIn(draft: chosenStyle, choseStyle: true)

        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(harness.styleProfiles.hasCompletedOnboarding)
        XCTAssertFalse(harness.styleProfiles.needsRemoteSync)
        XCTAssertEqual(harness.styleProfiles.profile, chosenStyle)
        let requests = await harness.apiTransport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "PUT"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let body = try XCTUnwrap(requests.last).jsonBody()
        XCTAssertEqual(body["onboarding_completed"] as? Bool, true)
        let style = try XCTUnwrap(body["style_profile"] as? [String: Any])
        XCTAssertEqual(style["axes"] as? [String: String], ["silhouette": "first"])
        XCTAssertEqual(style["occasions"] as? [String], ["work"])
    }

    func testReturningUserWhoSkippedKeepsTheirSavedStyle() async throws {
        let harness = try makeHarness(
            signedIn: true,
            api: [
                .response(
                    status: 200,
                    body: AuthFixtures.profileBody(style: ["palettes": ["colour"]], onboardingCompleted: true))
            ]
        )
        await harness.model.start()

        let outcome = try await harness.model.finishSignIn(draft: .empty, choseStyle: true)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(harness.styleProfiles.profile.palettes, [.colour])
        let methods = await harness.apiTransport.requests.map(\.httpMethod)
        XCTAssertEqual(methods, ["GET"], "Skipping must not overwrite an existing profile")
    }

    func testNewAccountFromWelcomeContinuesOnboarding() async throws {
        let harness = try makeHarness(
            signedIn: true, api: [.response(status: 200, body: AuthFixtures.profileBody(onboardingCompleted: false))])
        await harness.model.start()

        let outcome = try await harness.model.finishSignIn(draft: .empty, choseStyle: false)

        XCTAssertEqual(outcome, .needsStyleProfile)
        XCTAssertFalse(harness.styleProfiles.hasCompletedOnboarding)
    }

    func testDeletingTheAccountRemovesEverythingOnDevice() async throws {
        let harness = try makeHarness(signedIn: true, api: [.response(status: 200, body: AuthFixtures.deletionBody())])
        harness.styleProfiles.adoptRemote(chosenStyle)
        await harness.model.start()

        let result = try await harness.model.deleteAccount()

        XCTAssertEqual(result.status, "completed")
        XCTAssertEqual(harness.model.state, .signedOut)
        XCTAssertNil(harness.sessions.load())
        XCTAssertFalse(harness.styleProfiles.hasCompletedOnboarding)
        let request = await harness.apiTransport.requests.first
        XCTAssertEqual(request?.httpMethod, "DELETE")
        XCTAssertEqual(request?.url?.path(), "/v1/me")
    }

    func testFailedDeletionKeepsTheUserSignedIn() async throws {
        let body = AuthFixtures.json([
            "code": "service_unavailable", "message": "Grymode is temporarily unavailable. Please try again.",
            "request_id": "req-1", "retryable": false,
        ])
        let harness = try makeHarness(signedIn: true, api: [.response(status: 503, body: body)])
        await harness.model.start()

        let error = await capturedError { try await harness.model.deleteAccount() }

        XCTAssertEqual(error?.apiCode, "service_unavailable")
        XCTAssertEqual(error?.requestID, "req-1")
        XCTAssertTrue(harness.model.isSignedIn)
        XCTAssertNotNil(harness.sessions.load())
    }

    func testFailedStyleUploadIsFlaggedAndRetried() async throws {
        let harness = try makeHarness(
            signedIn: true,
            api: [
                .failure(.notConnectedToInternet), .failure(.notConnectedToInternet), .failure(.notConnectedToInternet),
                .response(status: 200, body: AuthFixtures.profileBody(onboardingCompleted: true)),
            ])
        harness.styleProfiles.adoptRemote(.empty)
        await harness.model.start()

        harness.styleProfiles.save(chosenStyle)
        await harness.model.syncStyleProfileIfNeeded()

        XCTAssertEqual(harness.model.syncState, .failed(.offline))
        XCTAssertTrue(harness.styleProfiles.needsRemoteSync)

        await harness.model.syncStyleProfileIfNeeded()

        XCTAssertEqual(harness.model.syncState, .idle)
        XCTAssertFalse(harness.styleProfiles.needsRemoteSync)
    }

    func testSignOutForgetsTheSessionAndPreferences() async throws {
        let harness = try makeHarness(signedIn: true, auth: [.response(status: 204)])
        harness.styleProfiles.adoptRemote(chosenStyle)
        await harness.model.start()

        await harness.model.signOut()

        XCTAssertEqual(harness.model.state, .signedOut)
        XCTAssertNil(harness.sessions.load())
        XCTAssertEqual(harness.styleProfiles.profile, .empty)
        let logout = await harness.authTransport.requests.first
        XCTAssertEqual(logout?.url?.path(), "/auth/v1/logout")
    }
}
