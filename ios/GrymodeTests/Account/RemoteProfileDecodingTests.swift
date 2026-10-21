import XCTest

@testable import Grymode

final class RemoteProfileDecodingTests: XCTestCase {
    func testDecodesLiveAPITimestampsWithFractionalSeconds() throws {
        let json = """
            {
              "id": "f5781661-b9e5-412f-9d01-543b5bde4301",
              "email": "uitest@grymode.test",
              "display_name": null,
              "style_profile": {
                "axes": { "character": "second" },
                "occasions": [],
                "palettes": []
              },
              "onboarding_completed_at": "2026-10-10T13:21:34.164451Z",
              "created_at": "2026-10-10T13:21:31.050968Z",
              "updated_at": "2026-10-10T13:21:34.164451Z"
            }
            """

        let profile = try JSONCoding.makeDecoder().decode(RemoteProfile.self, from: Data(json.utf8))

        XCTAssertNotNil(profile.onboardingCompletedAt)
        XCTAssertEqual(profile.styleProfile.axes[.character], .second)
    }
}
