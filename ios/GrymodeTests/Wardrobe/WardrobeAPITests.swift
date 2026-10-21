import XCTest

@testable import Grymode

final class WardrobeAPITests: XCTestCase {
    func testSummaryDecodesTheServerShape() throws {
        let data = WardrobeFixtures.summary(
            garments: [WardrobeFixtures.garment(category: "tops", confirmed: true)],
            jobs: [WardrobeFixtures.job(status: "succeeded")]
        )

        let summary = try JSONCoding.makeDecoder().decode(WardrobeSummary.self, from: data)

        XCTAssertEqual(summary.garments.count, 1)
        XCTAssertEqual(summary.garments[0].category, .tops)
        XCTAssertTrue(summary.garments[0].userConfirmed)
        XCTAssertEqual(summary.jobs[0].status, .succeeded)
        XCTAssertEqual(summary.confirmedCount, 1)
        XCTAssertEqual(summary.unconfirmedCount, 0)
        XCTAssertEqual(summary.garments[0].imageUrl, "https://storage.example.test/sign/read")
    }

    func testCreateUploadEncodesSnakeCaseBody() throws {
        let clientUploadId = WardrobeFixtures.mediaID
        let endpoint = try WardrobeAPI.createUpload(
            mediaType: .photo,
            contentType: "image/jpeg",
            byteSize: 2048,
            clientUploadId: clientUploadId
        )
        let body = try XCTUnwrap(endpoint.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.path, "/v1/wardrobe/uploads")
        XCTAssertEqual(endpoint.idempotencyKey, clientUploadId.uuidString.lowercased())
        XCTAssertEqual(json["media_type"] as? String, "photo")
        XCTAssertEqual(json["content_type"] as? String, "image/jpeg")
        XCTAssertEqual(json["byte_size"] as? Int, 2048)
        XCTAssertEqual(json["client_upload_id"] as? String, clientUploadId.uuidString.lowercased())
    }

    func testUpdateGarmentOmitsNilFields() throws {
        let endpoint = try WardrobeAPI.updateGarment(id: WardrobeFixtures.garmentID, category: .knitwear)
        let body = try XCTUnwrap(endpoint.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(endpoint.method, .patch)
        XCTAssertEqual(
            endpoint.path, "/v1/wardrobe/garments/\(WardrobeFixtures.garmentID.uuidString.lowercased())")
        XCTAssertEqual(Set(json.keys), ["category"])
        XCTAssertEqual(json["category"] as? String, "knitwear")
    }

    func testConfirmEncodesOptionalGarmentIds() throws {
        let ids = [WardrobeFixtures.garmentID]
        let endpoint = try WardrobeAPI.confirm(garmentIds: ids)
        let body = try XCTUnwrap(endpoint.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.path, "/v1/wardrobe/confirm")
        XCTAssertNotNil(endpoint.idempotencyKey)
        XCTAssertEqual(json["garment_ids"] as? [String], [WardrobeFixtures.garmentID.uuidString.lowercased()])
    }

    func testDeleteGarmentIsAuthenticatedDelete() {
        let endpoint = WardrobeAPI.deleteGarment(id: WardrobeFixtures.garmentID)
        XCTAssertEqual(endpoint.method, .delete)
        XCTAssertTrue(endpoint.requiresAuthentication)
        XCTAssertEqual(endpoint.retryPolicy, .standard)
    }
}
