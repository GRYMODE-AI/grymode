import XCTest

@testable import Grymode

@MainActor
final class WardrobeModelTests: XCTestCase {
    func testUploadThenConfirmHappyPath() async throws {
        let jpeg = try WardrobeFixtures.tinyJPEG()
        let draft = WardrobeFixtures.garment(category: "uncategorised", confirmed: false)
        let labeled = WardrobeFixtures.garment(category: "tops", confirmed: false)
        let confirmed = WardrobeFixtures.garment(category: "tops", confirmed: true)

        let transport = StubTransport([
            .response(status: 200, body: WardrobeFixtures.uploadSlot()),
            .response(status: 200),
            .response(status: 200, body: WardrobeFixtures.completeUpload()),
            .response(
                status: 200,
                body: WardrobeFixtures.summary(
                    garments: [draft],
                    jobs: [WardrobeFixtures.job(status: "succeeded")]
                )
            ),
            .response(status: 200, body: WardrobeFixtures.json(labeled)),
            .response(status: 200, body: WardrobeFixtures.json(["confirmed_count": 1])),
            .response(
                status: 200,
                body: WardrobeFixtures.summary(garments: [confirmed], jobs: [WardrobeFixtures.job()])
            ),
        ])
        let api = AuthFixtures.makeAPIClient(transport, tokens: StubTokenProvider(current: "access-1"))
        let model = WardrobeModel(api: api, sleep: { _ in }, maxPollAttempts: 3, pollInterval: 0)

        await model.uploadPhotoData([jpeg])

        XCTAssertEqual(model.uploadPhase, .idle)
        XCTAssertEqual(model.garments.count, 1)
        XCTAssertTrue(model.garments[0].needsLabel)

        try await model.updateCategory(garmentId: WardrobeFixtures.garmentID, category: .tops)
        XCTAssertEqual(model.garments[0].category, .tops)
        XCTAssertEqual(model.confirmableGarments.count, 1)

        await model.confirmLabeledPieces()

        XCTAssertNil(model.actionError)
        XCTAssertEqual(model.garments.count, 1)
        XCTAssertTrue(model.garments[0].userConfirmed)
        XCTAssertTrue(model.confirmableGarments.isEmpty)

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/v1/wardrobe/uploads")
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].url, WardrobeFixtures.uploadURL)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(requests[2].httpMethod, "POST")
        XCTAssertTrue(requests[2].url?.path.contains("/complete") == true)
        XCTAssertEqual(requests[3].httpMethod, "GET")
        XCTAssertEqual(requests[4].httpMethod, "PATCH")
        XCTAssertEqual(requests[5].httpMethod, "POST")
        XCTAssertEqual(requests[5].url?.path, "/v1/wardrobe/confirm")
        XCTAssertEqual(requests[6].httpMethod, "GET")
    }

    func testUploadFailsWhenAPIMissing() async {
        let model = WardrobeModel(api: nil)
        await model.uploadPhotoData([Data([0xFF, 0xD8, 0xFF])])
        guard case .failed(let error) = model.uploadPhase else {
            return XCTFail("Expected configuration failure")
        }
        XCTAssertEqual(
            error, .configuration("The Grymode API isn't configured for this build."))
    }

    func testConfirmRequiresLabeledPieces() async throws {
        let draft = WardrobeFixtures.garment(category: "uncategorised", confirmed: false)
        let transport = StubTransport([
            .response(status: 200, body: WardrobeFixtures.summary(garments: [draft]))
        ])
        let api = AuthFixtures.makeAPIClient(transport, tokens: StubTokenProvider(current: "access-1"))
        let model = WardrobeModel(api: api, sleep: { _ in })

        await model.refresh()
        await model.confirmLabeledPieces()

        XCTAssertEqual(model.actionError?.apiCode, "nothing_to_confirm")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET"])
    }
}
