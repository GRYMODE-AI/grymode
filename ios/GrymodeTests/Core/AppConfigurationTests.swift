import XCTest

@testable import Grymode

final class AppConfigurationTests: XCTestCase {
    private func load(
        environment: String?,
        url: String?,
        supabaseURL: String? = "https://project.supabase.co",
        publishableKey: String? = "sb_publishable_abc"
    ) -> Result<AppConfiguration, AppError> {
        var info: [String: Any] = [:]
        info[AppConfiguration.Key.environment] = environment
        info[AppConfiguration.Key.apiBaseURL] = url
        info[AppConfiguration.Key.supabaseURL] = supabaseURL
        info[AppConfiguration.Key.supabasePublishableKey] = publishableKey
        return Result { () throws(AppError) in try AppConfiguration.load(from: info) }
    }

    func testProductionRequiresHTTPS() throws {
        let config = try load(environment: "production", url: "https://api.grymode.com").get()
        XCTAssertEqual(config.environment, .production)
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://api.grymode.com")
        XCTAssertEqual(config.supabaseURL.absoluteString, "https://project.supabase.co")
        XCTAssertEqual(config.supabasePublishableKey, "sb_publishable_abc")

        XCTAssertEqual(
            load(environment: "production", url: "http://localhost:8000"),
            .failure(.configuration("The Grymode API address must use HTTPS."))
        )
        XCTAssertEqual(
            load(environment: "production", url: "https://api.grymode.com", supabaseURL: "http://127.0.0.1:54321"),
            .failure(.configuration("The sign-in service address must use HTTPS."))
        )
    }

    func testDevelopmentAllowsPlainHTTPOnlyForLoopback() throws {
        XCTAssertNoThrow(try load(environment: "development", url: "http://localhost:8000").get())
        XCTAssertNoThrow(try load(environment: "development", url: "http://127.0.0.1:8000").get())
        XCTAssertNoThrow(try load(environment: "development", url: "https://staging.example.test").get())
        XCTAssertNoThrow(
            try load(environment: "development", url: "http://localhost:8000", supabaseURL: "http://127.0.0.1:54321")
                .get())
        XCTAssertEqual(
            load(environment: "development", url: "http://192.168.1.20:8000"),
            .failure(.configuration("The Grymode API address must use HTTPS."))
        )
    }

    func testMissingOrInvalidValuesAreConfigurationErrors() {
        XCTAssertEqual(
            load(environment: "production", url: ""),
            .failure(.configuration("The Grymode API address has not been set for this build."))
        )
        XCTAssertEqual(
            load(environment: "production", url: nil),
            .failure(.configuration("The Grymode API address has not been set for this build."))
        )
        XCTAssertEqual(
            load(environment: "staging", url: "https://api.grymode.com"),
            .failure(.configuration("The build environment is missing or unrecognised."))
        )
        XCTAssertEqual(
            load(environment: "production", url: "not a url"),
            .failure(.configuration("The Grymode API address is not a valid URL."))
        )
        XCTAssertEqual(
            load(environment: "production", url: "https://api.grymode.com", supabaseURL: ""),
            .failure(.configuration("The sign-in service address has not been set for this build."))
        )
        XCTAssertEqual(
            load(environment: "production", url: "https://api.grymode.com", publishableKey: " "),
            .failure(.configuration("The sign-in service key has not been set for this build."))
        )
    }

    func testRefusesToShipASecretKey() {
        XCTAssertEqual(
            load(environment: "production", url: "https://api.grymode.com", publishableKey: "sb_secret_abc"),
            .failure(.configuration("This build contains a secret key. Use the publishable key instead."))
        )
    }

    func testDebugBundleIsConfiguredForLocalDevelopment() throws {
        let config = try AppConfiguration.load(from: Bundle.main)
        XCTAssertEqual(config.environment, .development)
        XCTAssertEqual(config.apiBaseURL.host(), "127.0.0.1")
        XCTAssertEqual(config.supabaseURL.host(), "127.0.0.1")
        XCTAssertTrue(config.supabasePublishableKey.hasPrefix("sb_publishable_"))
    }
}
