import XCTest

@testable import Grymode

final class StyleProfileTests: XCTestCase {
    func testTogglingAxisSelectsSwitchesAndClears() {
        var profile = StyleProfile.empty
        profile.toggle(.first, on: .silhouette)
        XCTAssertEqual(profile.axes[.silhouette], .first)
        profile.toggle(.second, on: .silhouette)
        XCTAssertEqual(profile.axes[.silhouette], .second)
        profile.toggle(.second, on: .silhouette)
        XCTAssertNil(profile.axes[.silhouette])
        XCTAssertTrue(profile.isEmpty)
    }

    func testMultiSelectToggles() {
        var profile = StyleProfile.empty
        profile.toggle(Occasion.travel)
        profile.toggle(Occasion.work)
        profile.toggle(PalettePreference.colour)
        XCTAssertEqual(profile.orderedOccasions, [.work, .travel])
        XCTAssertEqual(profile.orderedPalettes, [.colour])
        profile.toggle(Occasion.work)
        XCTAssertEqual(profile.orderedOccasions, [.travel])
        XCTAssertFalse(profile.isEmpty)
    }

    func testDescriptorsFollowAxisOrderAndHeadline() {
        var profile = StyleProfile.empty
        XCTAssertEqual(profile.headline, "Open to everything")
        profile.toggle(.second, on: .finish)
        profile.toggle(.first, on: .silhouette)
        XCTAssertEqual(profile.descriptors, ["Relaxed", "Refined"])
        XCTAssertEqual(profile.headline, "Relaxed · Refined")
    }

    func testCodableRoundTrip() throws {
        var profile = StyleProfile.empty
        profile.toggle(.second, on: .character)
        profile.toggle(Occasion.eveningsOut)
        profile.toggle(PalettePreference.earthTones)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"character\""), "Axes should encode as a keyed object: \(json)")
    }

    func testEveryAxisHasDistinctLabels() {
        for axis in StyleAxis.allCases {
            XCTAssertNotEqual(axis.label(for: .first), axis.label(for: .second))
            XCTAssertFalse(axis.question.isEmpty)
        }
    }
}
