import XCTest

@testable import Grymode

final class AccountAPITests: XCTestCase {
    func testRemoteProfileDecodesTheServerShape() throws {
        let data = AuthFixtures.profileBody(
            style: ["axes": ["finish": "second"], "occasions": ["eveningsOut"], "palettes": ["earthTones"]],
            onboardingCompleted: true
        )

        let profile = try JSONCoding.makeDecoder().decode(RemoteProfile.self, from: data)

        XCTAssertEqual(profile.id, AuthFixtures.userID)
        XCTAssertNil(profile.displayName)
        XCTAssertEqual(profile.styleProfile.axes, [.finish: .second])
        XCTAssertEqual(profile.styleProfile.occasions, [.eveningsOut])
        XCTAssertEqual(profile.styleProfile.palettes, [.earthTones])
        XCTAssertNotNil(profile.onboardingCompletedAt)
    }

    func testStyleUpdateEncodesWhatTheServerAccepts() throws {
        var style = StyleProfile.empty
        style.toggle(.second, on: .character)
        style.toggle(PalettePreference.blackAndWhite)

        let endpoint = try AccountAPI.updateStyleProfile(style, onboardingCompleted: true)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(endpoint.body)) as? [String: Any])

        XCTAssertEqual(endpoint.method, .put)
        XCTAssertEqual(endpoint.path, "/v1/me/style-profile")
        XCTAssertEqual(Set(body.keys), ["style_profile", "onboarding_completed"])
        let encoded = try XCTUnwrap(body["style_profile"] as? [String: Any])
        XCTAssertEqual(encoded["axes"] as? [String: String], ["character": "second"])
        XCTAssertEqual(encoded["palettes"] as? [String], ["blackAndWhite"])
        XCTAssertEqual(encoded["occasions"] as? [String], [])
    }

    func testAccountDeletionIsAnAuthenticatedRetryableDelete() {
        let endpoint = AccountAPI.deleteAccount()

        XCTAssertEqual(endpoint.method, .delete)
        XCTAssertEqual(endpoint.path, "/v1/me")
        XCTAssertTrue(endpoint.requiresAuthentication)
        XCTAssertEqual(endpoint.retryPolicy, .standard)
    }
}
