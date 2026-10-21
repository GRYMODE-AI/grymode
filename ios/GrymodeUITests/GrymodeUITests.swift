import XCTest

/// End-to-end journeys against the local stack (see `UITestSupport`).
@MainActor
final class GrymodeUITests: XCTestCase {
    override func setUp() async throws {
        try await requireLocalStack()
    }

    func testSkippingStyleDiscoveryThenSigningInReachesEverySection() async throws {
        let app = launchFresh()

        tap("welcome.getStarted", in: app)
        tap("styleIntro.skip", in: app)
        XCTAssertTrue(app.staticTexts["Open to everything"].waitForExistence(timeout: UITestTimeouts.step))
        tap("styleResult.continue", in: app)
        try await signIn(email: Self.makeTestEmail(), in: app)

        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)
        for id in ["style", "wardrobe", "looks", "profile", "home"] {
            open(section: id, in: app)
        }
    }

    func testChosenPreferencesAreSavedToTheAccountAndSurviveRelaunch() async throws {
        let app = launchFresh()

        tap("welcome.getStarted", in: app)
        tap("styleIntro.choose", in: app)
        tap("preference.silhouette.first", in: app)
        tap("preference.finish.second", in: app)
        tap("preferences.continue", in: app)
        XCTAssertTrue(app.staticTexts["Relaxed · Refined"].waitForExistence(timeout: UITestTimeouts.step))
        tap("styleResult.continue", in: app)
        try await signIn(email: Self.makeTestEmail(), in: app)

        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)
        open(section: "style", in: app)
        XCTAssertTrue(app.staticTexts["Relaxed · Refined"].waitForExistence(timeout: UITestTimeouts.step))

        // Session recovery: relaunching without a reset goes straight back in.
        app.terminate()
        app.launchArguments = []
        app.launch()
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.launch)
        open(section: "style", in: app)
        XCTAssertTrue(app.staticTexts["Relaxed · Refined"].waitForExistence(timeout: UITestTimeouts.step))
    }

    func testSigningOutAndBackInRestoresTheStyleProfileFromTheAccount() async throws {
        let app = launchFresh()
        let email = Self.makeTestEmail()

        tap("welcome.getStarted", in: app)
        tap("styleIntro.choose", in: app)
        tap("preference.character.second", in: app)
        tap("preferences.continue", in: app)
        tap("styleResult.continue", in: app)
        try await signIn(email: email, in: app)
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)

        open(section: "profile", in: app)
        XCTAssertTrue(app.staticTexts[email].waitForExistence(timeout: UITestTimeouts.step))
        tap("account.signOut", in: app)
        tapDialogButton("Sign out", excluding: ["account.signOut"], in: app)
        assertScreen("screen.welcome", in: app, timeout: UITestTimeouts.network)

        tap("welcome.signIn", in: app)
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: UITestTimeouts.step))
        try await signIn(email: email, in: app)
        // Returning-user finish can take a moment after verify; allow the longer mail window.
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.mail)
        open(section: "style", in: app)
        XCTAssertTrue(app.staticTexts["Contemporary"].waitForExistence(timeout: UITestTimeouts.step))
    }

    func testDeletingTheAccountExplainsSubscriptionsAndReturnsToWelcome() async throws {
        let app = launchFresh()

        tap("welcome.getStarted", in: app)
        tap("styleIntro.skip", in: app)
        tap("styleResult.continue", in: app)
        try await signIn(email: Self.makeTestEmail(), in: app)
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)

        open(section: "profile", in: app)
        tap("account.delete", in: app)
        assertScreen("screen.deleteAccount", in: app)
        XCTAssertTrue(
            app.staticTexts["Your subscription isn't cancelled automatically"].waitForExistence(
                timeout: UITestTimeouts.step))
        tap("deleteAccount.delete", in: app)
        tapDialogButton("Delete account", excluding: ["deleteAccount.delete", "account.delete"], in: app)

        assertScreen("screen.welcome", in: app, timeout: UITestTimeouts.network)
    }

    func testLooksEmptyStateOffersCreateLooks() async throws {
        let app = launchFresh()
        tap("welcome.getStarted", in: app)
        tap("styleIntro.skip", in: app)
        tap("styleResult.continue", in: app)
        try await signIn(email: Self.makeTestEmail(), in: app)
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)

        open(section: "looks", in: app)
        assertScreen("screen.looks", in: app)
        let createLooks = app.buttons["looks.generate"]
        XCTAssertTrue(createLooks.waitForExistence(timeout: UITestTimeouts.step))
        open(section: "wardrobe", in: app)
        assertScreen("screen.wardrobe", in: app)
    }
}
