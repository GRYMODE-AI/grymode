import XCTest

/// Signs into the seeded wardrobe account and writes marketing screenshots for the landing page.
///
///     TEST_RUNNER_GRYMODE_LANDING_SHOTS=1 \
///     TEST_RUNNER_GRYMODE_SHOT_DIR="/path/to/landing-page/public/images" \
///     TEST_RUNNER_GRYMODE_REQUIRE_STACK=1 \
///     xcodebuild test -only-testing:GrymodeUITests/LandingPageScreenshotTests ...
@MainActor
final class LandingPageScreenshotTests: XCTestCase {
    private static let seededEmail = "abiolayoung229@gmail.com"

    func testCaptureWardrobeScreensForLanding() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["GRYMODE_LANDING_SHOTS"] == "1", "Landing screenshot capture not requested")
        try await requireLocalStack()

        let shotDir = environment["GRYMODE_SHOT_DIR"]
            ?? "\(NSTemporaryDirectory())grymode-landing-shots"
        try FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)

        XCUIDevice.shared.orientation = .portrait
        let app = launchFresh()

        tap("welcome.signIn", in: app)
        try await signIn(email: Self.seededEmail, in: app)
        assertScreen("screen.home", in: app, timeout: UITestTimeouts.network)

        // Give remote look / garment images a moment to paint.
        try await Task.sleep(for: .seconds(3))
        saveShot("app-home", to: shotDir)

        open(section: "wardrobe", in: app)
        try await Task.sleep(for: .seconds(2))
        saveShot("app-wardrobe", to: shotDir)

        open(section: "looks", in: app)
        try await Task.sleep(for: .seconds(2))
        saveShot("app-looks", to: shotDir)

        open(section: "home", in: app)
        try await Task.sleep(for: .seconds(1))
        saveShot("app-home-alt", to: shotDir)
    }

    private func saveShot(_ name: String, to directory: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        do {
            try data.write(to: url, options: .atomic)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not write \(url.path): \(error)")
        }
    }
}
