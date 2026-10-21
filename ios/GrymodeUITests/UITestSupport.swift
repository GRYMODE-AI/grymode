import XCTest

/// Shared steps for the end-to-end UI tests. These run against the real local stack:
/// Supabase (`supabase start`) for sign-in, the Grymode API on localhost:8000, and Mailpit,
/// where Supabase delivers sign-in emails locally. See docs/environment.md.
enum UITestTimeouts {
    static let step: TimeInterval = 10
    /// A cold simulator can take well over a minute to bring up its accessibility server after launch.
    static let launch: TimeInterval = 120
    static let network: TimeInterval = 30
    /// Waiting for Mailpit after a resend can exceed the usual network window.
    static let mail: TimeInterval = 45
}

@MainActor
extension XCTestCase {
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func tap(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier, in: app)
        XCTAssertTrue(
            target.waitForExistence(timeout: UITestTimeouts.step), "Missing \(identifier)", file: file, line: line)
        target.tap()
    }

    func assertScreen(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = UITestTimeouts.step,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element(identifier, in: app).waitForExistence(timeout: timeout), "Expected \(identifier)", file: file,
            line: line)
    }

    /// Selects a section through whichever navigation container is showing: the tab bar
    /// (compact width) or the sidebar (regular width).
    func open(section id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Prefer an identifier when present; fall back to the tab label. Always resolve to a
        // single element — some simulators briefly expose duplicate tab-bar queries.
        let byID = element("sidebar.\(id)", in: app)
        if byID.waitForExistence(timeout: 1) {
            byID.tap()
        } else {
            let tabButton = app.tabBars.buttons[id.capitalized].firstMatch
            XCTAssertTrue(
                tabButton.waitForExistence(timeout: UITestTimeouts.step), "Missing tab \(id)", file: file,
                line: line)
            tabButton.tap()
        }
        assertScreen("screen.\(id)", in: app, file: file, line: line)
    }

    /// Taps a confirmation-dialog button. Dialog buttons often share their label with the button
    /// that opened the dialog, so those identifiers are excluded.
    func tapDialogButton(
        _ label: String,
        excluding identifiers: [String],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label == %@ AND NOT (identifier IN %@)", label, identifiers)
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: UITestTimeouts.step), "Missing dialog button \(label)", file: file,
            line: line)
        button.tap()
    }

    func launchFresh() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingResetState"]
        app.launch()
        XCTAssertTrue(element("screen.welcome", in: app).waitForExistence(timeout: UITestTimeouts.launch))
        return app
    }

    /// Skips the test with instructions when the local stack isn't running, unless the run
    /// requires it (`TEST_RUNNER_GRYMODE_REQUIRE_STACK=1`), in which case it fails.
    func requireLocalStack() async throws {
        if await Mailpit.isReachable() { return }
        let message = "Local stack not running. Start it with scripts/dev-stack.sh (see docs/environment.md)."
        if ProcessInfo.processInfo.environment["GRYMODE_REQUIRE_STACK"] == "1" {
            XCTFail(message)
            throw XCTSkip(message)
        }
        throw XCTSkip(message)
    }

    static func makeTestEmail() -> String {
        "uitest-\(UUID().uuidString.prefix(12).lowercased())@grymode.test"
    }

    /// Completes the email sign-in screens: enters the address, reads the code Supabase emailed
    /// to Mailpit, and enters it.
    func signIn(email: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) async throws
    {
        assertScreen("screen.signIn", in: app, file: file, line: line)
        let previous = try await Mailpit.messageIDs(to: email)

        let emailField = element("signIn.email", in: app)
        XCTAssertTrue(emailField.waitForExistence(timeout: UITestTimeouts.step), file: file, line: line)
        emailField.tap()
        emailField.typeText(email)
        tap("signIn.sendCode", in: app, file: file, line: line)

        assertScreen("screen.verifyCode", in: app, timeout: UITestTimeouts.network, file: file, line: line)
        // Per-address throttle: the app opens verify without a new email. That earlier code may
        // already have been used (sign-out then immediate sign-in), so wait and request a fresh one.
        let throttled = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "less than a minute ago"))
            .firstMatch
        if throttled.exists {
            try await waitAndResendCode(in: app, file: file, line: line)
        }
        let code = try await Mailpit.waitForCode(to: email, excluding: previous)
        let codeField = element("verify.code", in: app)
        codeField.tap()
        codeField.typeText(code)
        // Auto-submit runs after the sixth digit; give the account finish call a moment.
        _ = element("screen.home", in: app).waitForExistence(timeout: UITestTimeouts.network)
    }

    /// Waits out Supabase's per-address OTP interval, then taps "Send a new code".
    private func waitAndResendCode(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let resend = element("verify.resend", in: app)
        XCTAssertTrue(resend.waitForExistence(timeout: UITestTimeouts.step), file: file, line: line)
        let deadline = Date().addingTimeInterval(75)
        while Date() < deadline {
            if resend.isEnabled, resend.label == "Send a new code" {
                resend.tap()
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        XCTFail("Resend stayed disabled after the OTP throttle window", file: file, line: line)
    }
}

/// Reads sign-in emails from the local Mailpit inbox (http://127.0.0.1:54324).
enum Mailpit {
    private static let baseURL = URL(string: "http://127.0.0.1:54324/api/v1/") ?? URL(fileURLWithPath: "/")

    struct NoCodeError: Error {}

    private struct SearchResult: Decodable {
        struct Summary: Decodable {
            let id: String
            enum CodingKeys: String, CodingKey { case id = "ID" }
        }
        let messages: [Summary]
    }

    private struct Message: Decodable {
        let text: String
        enum CodingKeys: String, CodingKey { case text = "Text" }
    }

    /// Retries because a loaded host can take several seconds to answer the first request.
    static func isReachable() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "info"))
        request.timeoutInterval = 10
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
            if let (_, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse)?.statusCode == 200
            {
                return true
            }
        }
        return false
    }

    /// Message IDs sent to `email`, newest first.
    static func messageIDs(to email: String) async throws -> [String] {
        var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "query", value: "to:\"\(email)\"")]
        let url = try XCTUnwrap(components?.url)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SearchResult.self, from: data).messages.map(\.id)
    }

    static func waitForCode(to email: String, excluding previous: [String]) async throws -> String {
        let deadline = Date().addingTimeInterval(UITestTimeouts.mail)
        while Date() < deadline {
            if let id = try await messageIDs(to: email).first(where: { !previous.contains($0) }) {
                return try await code(inMessage: id)
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTFail("No sign-in email arrived for \(email)")
        throw NoCodeError()
    }

    static func latestCode(to email: String) async throws -> String {
        guard let id = try await messageIDs(to: email).first else {
            XCTFail("No earlier sign-in email exists for \(email)")
            throw NoCodeError()
        }
        return try await code(inMessage: id)
    }

    private static func code(inMessage id: String) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appending(path: "message/\(id)"))
        let text = try JSONDecoder().decode(Message.self, from: data).text
        guard let range = text.range(of: #"\b\d{6}\b"#, options: .regularExpression) else {
            XCTFail("The sign-in email did not contain a 6-digit code")
            throw NoCodeError()
        }
        return String(text[range])
    }
}
