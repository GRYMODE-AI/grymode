import XCTest

/// Walks every screen and attaches a screenshot of each, for the layout review in
/// `docs/device-test-matrix.md`. Needs the local stack for the sign-in screens. Skipped unless
/// explicitly requested:
///
///     TEST_RUNNER_GRYMODE_SCREENSHOTS=1 [TEST_RUNNER_GRYMODE_ORIENTATION=landscape] xcodebuild test \
///       -only-testing:GrymodeUITests/LayoutScreenshotTests ...
@MainActor
final class LayoutScreenshotTests: XCTestCase {
    func testCaptureEveryScreen() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["GRYMODE_SCREENSHOTS"] == "1", "Screenshot capture not requested")
        try await requireLocalStack()

        XCUIDevice.shared.orientation = environment["GRYMODE_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait

        let app = launchFresh()
        capture("01-welcome")

        tap("welcome.getStarted", in: app)
        XCTAssertTrue(element("styleIntro.choose", in: app).waitForExistence(timeout: UITestTimeouts.step))
        capture("02-style-intro")

        tap("styleIntro.choose", in: app)
        tap("preference.silhouette.first", in: app)
        tap("preference.character.second", in: app)
        capture("03-preferences")

        tap("preferences.continue", in: app)
        XCTAssertTrue(element("styleResult.continue", in: app).waitForExistence(timeout: UITestTimeouts.step))
        capture("04-style-result")

        tap("styleResult.continue", in: app)
        assertScreen("screen.signIn", in: app)
        capture("05-sign-in")

        let email = Self.makeTestEmail()
        let previous = try await Mailpit.messageIDs(to: email)
        let emailField = element("signIn.email", in: app)
        emailField.tap()
        emailField.typeText(email)
        tap("signIn.sendCode", in: app)
        assertScreen("screen.verifyCode", in: app, timeout: UITestTimeouts.network)
        capture("06-verify-code")

        let code = try await Mailpit.waitForCode(to: email, excluding: previous)
        element("verify.code", in: app).typeText(code)
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)

        for (index, section) in ["home", "style", "wardrobe", "looks", "profile"].enumerated() {
            open(section: section, in: app)
            capture(String(format: "%02d-%@", index + 7, section))
        }

        tap("account.delete", in: app)
        assertScreen("screen.deleteAccount", in: app)
        capture("12-delete-account")
        app.buttons["Cancel"].firstMatch.tap()

        open(section: "style", in: app)
        tap("style.edit", in: app)
        assertScreen("screen.styleEditor", in: app)
        capture("13-style-editor")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
