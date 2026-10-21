import SwiftUI
import XCTest

@testable import Grymode

@MainActor
final class AppRouterTests: XCTestCase {
    func testStartsOnHomeAndSelectsTabs() {
        let router = AppRouter()
        XCTAssertEqual(router.selectedTab, .home)
        router.select(.looks)
        XCTAssertEqual(router.selectedTab, .looks)
    }

    func testResetToHomeClearsStacksAndSelection() {
        let router = AppRouter()
        var path = NavigationPath()
        path.append("item")
        router.setPath(path, for: .wardrobe)
        router.select(.profile)

        router.resetToHome()

        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertTrue(router.path(for: .wardrobe).isEmpty)
    }

    func testEachTabKeepsItsOwnPath() {
        let router = AppRouter()
        var wardrobePath = NavigationPath()
        wardrobePath.append("item-1")
        router.setPath(wardrobePath, for: .wardrobe)

        XCTAssertEqual(router.path(for: .wardrobe).count, 1)
        XCTAssertTrue(router.path(for: .looks).isEmpty)

        router.select(.looks)
        router.select(.wardrobe)
        XCTAssertEqual(router.path(for: .wardrobe).count, 1, "Switching sections must not discard navigation state")

        router.popToRoot(.wardrobe)
        XCTAssertTrue(router.path(for: .wardrobe).isEmpty)
    }

    func testSidebarSelectionIgnoresDeselection() {
        let router = AppRouter()
        let selection = router.sidebarSelection
        selection.wrappedValue = .profile
        XCTAssertEqual(router.selectedTab, .profile)
        selection.wrappedValue = nil
        XCTAssertEqual(router.selectedTab, .profile)
    }

    func testTabsHaveTitlesAndIcons() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.title.isEmpty)
            XCTAssertFalse(tab.systemImage.isEmpty)
        }
    }

    func testPhaseFollowsSessionAndOnboarding() async throws {
        let store = StyleProfileStore(defaults: try makeEphemeralDefaults())
        let service = AuthFixtures.makeAuthService(
            StubTransport([]), store: EphemeralSessionStore(session: AuthFixtures.session()))
        let account = AccountModel(auth: service, api: nil, styleProfiles: store)
        let model = AppModel(
            configuration: .failure(.unexpected), apiClient: nil, styleProfiles: store, account: account)
        XCTAssertEqual(model.phase, .launching)

        await account.start()
        XCTAssertEqual(model.phase, .onboarding, "Signed in but onboarding not finished")

        // Completing onboarding through AccountModel (not the store alone) must move phase to main —
        // that is the path the sign-in screens use after verify.
        let api = StubTransport([
            .response(
                status: 200,
                body: AuthFixtures.profileBody(style: ["axes": ["character": "second"]], onboardingCompleted: true))
        ])
        let accountWithAPI = AccountModel(
            auth: service, api: AuthFixtures.makeAPIClient(api, tokens: service), styleProfiles: store)
        let modelWithAPI = AppModel(
            configuration: .failure(.unexpected), apiClient: nil, styleProfiles: store, account: accountWithAPI)
        await accountWithAPI.start()
        _ = try await accountWithAPI.finishSignIn(draft: .empty, choseStyle: false)
        XCTAssertEqual(modelWithAPI.phase, .main)
        XCTAssertEqual(store.profile.axes[.character], .second)

        await service.endSession()
        await Task.yield()
        try await waitUntil { modelWithAPI.phase == .onboarding }
    }

    func testSignedOutUsersAlwaysSeeOnboarding() async throws {
        let store = StyleProfileStore(defaults: try makeEphemeralDefaults())
        let account = AccountModel(auth: nil, api: nil, styleProfiles: store)
        let model = AppModel(
            configuration: .failure(.unexpected), apiClient: nil, styleProfiles: store, account: account)

        await account.start()

        XCTAssertEqual(model.phase, .onboarding)
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Condition not met in time")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testHomeGreetingFollowsTimeOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func date(hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour)))
        }
        XCTAssertEqual(HomeView.greeting(for: try date(hour: 8), calendar: calendar), "Good morning")
        XCTAssertEqual(HomeView.greeting(for: try date(hour: 14), calendar: calendar), "Good afternoon")
        XCTAssertEqual(HomeView.greeting(for: try date(hour: 21), calendar: calendar), "Good evening")
        XCTAssertEqual(HomeView.greeting(for: try date(hour: 2), calendar: calendar), "Good evening")
    }
}
