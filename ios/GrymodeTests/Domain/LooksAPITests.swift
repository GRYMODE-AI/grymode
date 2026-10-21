import XCTest

@testable import Grymode

final class LooksAPITests: XCTestCase {
    func testLibraryQueryIncludesOccasionAndSavedOnly() {
        let endpoint = LooksAPI.library(occasion: "work", savedOnly: true)
        XCTAssertEqual(endpoint.path, "/v1/outfits")
        XCTAssertEqual(endpoint.queryItems.map(\.name), ["occasion", "saved_only"])
        XCTAssertEqual(endpoint.queryItems.map(\.value), ["work", "true"])
    }

    func testHomeAndSavePaths() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        XCTAssertEqual(LooksAPI.home().path, "/v1/home")
        XCTAssertEqual(LooksAPI.save(id: id).method, .post)
        XCTAssertEqual(LooksAPI.save(id: id).path, "/v1/outfits/11111111-1111-1111-1111-111111111111/save")
        XCTAssertEqual(LooksAPI.unsave(id: id).method, .delete)
    }

    func testOutfitLookWithSavedToggle() {
        let look = OutfitLook(
            id: UUID(),
            title: "Test",
            occasionTags: ["work"],
            styleTags: [],
            contextualTags: [],
            score: 1,
            isFreeReveal: true,
            isLocked: false,
            isSaved: false,
            pieceCount: 2,
            garments: [],
            createdAt: .now
        )
        XCTAssertTrue(look.withSaved(true).isSaved)
        XCTAssertFalse(look.withSaved(true).withSaved(false).isSaved)
    }
}
