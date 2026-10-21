import XCTest

@testable import Grymode

@MainActor
final class OnboardingModelTests: XCTestCase {
    private func makeModel(
        signedIn: Bool = false,
        api: [StubTransport.Outcome] = []
    ) async throws -> (OnboardingModel, StyleProfileStore, StubTransport) {
        let store = StyleProfileStore(defaults: try makeEphemeralDefaults())
        let service = AuthFixtures.makeAuthService(
            StubTransport([]), store: EphemeralSessionStore(session: signedIn ? AuthFixtures.session() : nil))
        let apiTransport = StubTransport(api)
        let account = AccountModel(
            auth: service, api: AuthFixtures.makeAPIClient(apiTransport, tokens: service), styleProfiles: store)
        await account.start()
        return (OnboardingModel(store: store, account: account), store, apiTransport)
    }

    func testSignedOutUsersSignInAfterTheResult() async throws {
        let (model, store, _) = try await makeModel()
        model.begin()
        model.choosePreferences()
        model.draft.toggle(.first, on: .silhouette)
        model.showResult()

        await model.continueFromResult()

        XCTAssertEqual(model.path, [.styleIntro, .preferences, .result, .signIn])
        XCTAssertFalse(model.isReturningUser)
        XCTAssertFalse(store.hasCompletedOnboarding, "Onboarding completes only once the profile is in an account")
    }

    func testSignedInUsersSaveStraightFromTheResult() async throws {
        let saved = AuthFixtures.profileBody(style: ["axes": ["silhouette": "first"]], onboardingCompleted: true)
        let (model, store, transport) = try await makeModel(
            signedIn: true,
            api: [
                .response(status: 200, body: AuthFixtures.profileBody(onboardingCompleted: false)),
                .response(status: 200, body: saved),
            ])
        model.begin()
        model.choosePreferences()
        model.draft.toggle(.first, on: .silhouette)
        model.showResult()

        await model.continueFromResult()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.profile.axes[.silhouette], .first)
        XCTAssertNil(model.finishError)
        let methods = await transport.requests.map(\.httpMethod)
        XCTAssertEqual(methods, ["GET", "PUT"])
    }

    func testSaveFailureIsShownAndOnboardingStaysOpen() async throws {
        let (model, store, _) = try await makeModel(
            signedIn: true,
            api: Array(repeating: .failure(.notConnectedToInternet), count: 3))
        model.begin()
        model.skipPreferences()

        await model.continueFromResult()

        XCTAssertEqual(model.finishError, .offline)
        XCTAssertFalse(model.isFinishing)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testWelcomeSignInIsForReturningUsers() async throws {
        let (model, _, _) = try await makeModel()

        model.signInFromWelcome()

        XCTAssertEqual(model.path, [.signIn])
        XCTAssertTrue(model.isReturningUser)
    }

    func testSkippingDiscardsUnconfirmedChoices() async throws {
        let (model, _, _) = try await makeModel()
        model.begin()
        model.choosePreferences()
        model.draft.toggle(Occasion.work)

        model.skipPreferences()

        XCTAssertEqual(model.path.last, .avatar)
        XCTAssertEqual(model.draft, .empty)
    }

    func testEditPreferencesReturnsToTheFormKeepingDraft() async throws {
        let (model, _, _) = try await makeModel()
        model.begin()
        model.choosePreferences()
        model.draft.toggle(PalettePreference.neutrals)
        model.showResult()

        model.editPreferences()

        XCTAssertEqual(model.path, [.styleIntro, .preferences])
        XCTAssertEqual(model.draft.orderedPalettes, [.neutrals])
    }

    func testEditPreferencesAfterSkipOpensTheForm() async throws {
        let (model, _, _) = try await makeModel()
        model.begin()
        model.skipPreferences()

        model.editPreferences()

        XCTAssertEqual(model.path, [.styleIntro, .preferences])
    }

    func testUsingADifferentEmailReturnsToTheEmailStep() async throws {
        let (model, _, _) = try await makeModel()
        model.signInFromWelcome()
        model.path.append(.verifyCode)

        model.useDifferentEmail()

        XCTAssertEqual(model.path, [.signIn])
    }
}
