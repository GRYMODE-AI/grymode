import XCTest

@testable import Grymode

@MainActor
final class TryOnModelTests: XCTestCase {
    private let lookId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func session(status: String, views: [(String, String, String?)]) -> Data {
        AuthFixtures.json([
            "look_id": lookId.uuidString.lowercased(),
            "title": "Camel After Dark",
            "height_cm": 180,
            "body_build": "slim",
            "face_url": "https://cdn.test/face.jpg?token=a",
            "garment_image_urls": ["https://cdn.test/g1.jpg?token=a"],
            "preview_mode": "ai_multi_view",
            "status": status,
            "views": views.map { view, state, url in
                ["view": view, "status": state, "image_url": url as Any, "error_code": NSNull()]
            },
            "notice": "AI-rendered from your face photo.",
        ])
    }

    func testStartPollsUntilEveryAngleIsReady() async throws {
        let url = "https://cdn.test/r.jpg?token=a"
        let transport = StubTransport([
            .response(status: 200, body: session(status: "rendering", views: [("front", "running", nil)])),
            .response(
                status: 200,
                body: session(
                    status: "rendering",
                    views: [("front", "succeeded", url), ("three_quarter", "running", nil)]
                )
            ),
            .response(
                status: 200,
                body: session(
                    status: "ready",
                    views: [
                        ("front", "succeeded", url), ("three_quarter", "succeeded", url),
                        ("side", "succeeded", url), ("back", "succeeded", url),
                    ]
                )
            ),
        ])
        let api = AuthFixtures.makeAPIClient(transport, tokens: StubTokenProvider(current: "access-1"))
        let model = TryOnModel(lookId: lookId, api: api, sleep: { _ in }, pollInterval: 0, maxPolls: 5)

        await model.start()

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.session?.status, .ready)
        XCTAssertEqual(model.session?.previewMode, .aiMultiView)
        XCTAssertEqual(model.session?.readyCount, 4)
        XCTAssertNotNil(model.session?.render(for: .threeQuarter)?.imageURL)
        XCTAssertFalse(model.isRendering)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET", "GET"])
        XCTAssertEqual(requests[0].url?.path, "/v1/try-on/looks/\(lookId.uuidString.lowercased())")
    }

    func testMissingAvatarAsksForFitProfile() async {
        let body = AuthFixtures.json([
            "code": "invalid_request", "message": "Add a clear face photo.", "request_id": "req-1",
            "retryable": false,
        ])
        let transport = StubTransport([.response(status: 422, body: body)])
        let api = AuthFixtures.makeAPIClient(transport, tokens: StubTokenProvider(current: "access-1"))
        let model = TryOnModel(lookId: lookId, api: api, sleep: { _ in }, pollInterval: 0)

        await model.start()

        XCTAssertEqual(model.phase, .needsAvatar("Add a clear face photo."))
        XCTAssertNil(model.session)
    }

    func testPollingStopsAtLimitWhileStillRendering() async {
        let rendering = session(status: "rendering", views: [("front", "running", nil)])
        let transport = StubTransport(Array(repeating: .response(status: 200, body: rendering), count: 4))
        let api = AuthFixtures.makeAPIClient(transport, tokens: StubTokenProvider(current: "access-1"))
        let model = TryOnModel(lookId: lookId, api: api, sleep: { _ in }, pollInterval: 0, maxPolls: 2)

        await model.start()

        XCTAssertTrue(model.isRendering)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }
}

final class OutfitVisualDecodingTests: XCTestCase {
    func testDecodesStyledVisualAndPieceDetails() throws {
        let data = AuthFixtures.json([
            "id": "33333333-3333-3333-3333-333333333333",
            "title": "Blue City Stroll",
            "occasion_tags": ["Weekend"],
            "style_tags": [],
            "contextual_tags": [],
            "score": 0.9,
            "is_free_reveal": false,
            "is_locked": false,
            "is_saved": false,
            "piece_count": 1,
            "garments": [
                [
                    "garment_id": "44444444-4444-4444-4444-444444444444",
                    "category": "outerwear",
                    "slot": "outerwear",
                    "position": 0,
                    "image_url": "https://cdn.test/g.jpg?token=a",
                    "primary_color": "beige",
                    "subcategory": "trench coat",
                    "material": "cotton gabardine",
                ]
            ],
            "visual": ["status": "succeeded", "image_url": "https://cdn.test/look.jpg?token=a", "error_code": NSNull()],
            "created_at": "2026-10-13T12:00:00Z",
        ])

        let look = try JSONCoding.makeDecoder().decode(OutfitLook.self, from: data)

        XCTAssertEqual(look.styledImageURL?.absoluteString, "https://cdn.test/look.jpg?token=a")
        XCTAssertFalse(look.isStyling)
        XCTAssertEqual(look.garments[0].displayName, "Beige trench coat")
        XCTAssertEqual(look.garments[0].roleTitle, "Layer on top")
        XCTAssertEqual(look.withSaved(true).visual, look.visual)
    }

    func testPendingVisualIsStylingAndOlderPayloadsStillDecode() throws {
        var payload: [String: Any] = [
            "id": "33333333-3333-3333-3333-333333333333",
            "title": "Look",
            "occasion_tags": [],
            "style_tags": [],
            "contextual_tags": [],
            "score": NSNull(),
            "is_free_reveal": false,
            "is_locked": false,
            "is_saved": false,
            "piece_count": 0,
            "garments": [],
            "created_at": "2026-10-13T12:00:00Z",
        ]
        let legacy = try JSONCoding.makeDecoder().decode(OutfitLook.self, from: AuthFixtures.json(payload))
        XCTAssertNil(legacy.visual)
        XCTAssertFalse(legacy.isStyling)

        payload["visual"] = ["status": "running", "image_url": NSNull(), "error_code": NSNull()]
        let pending = try JSONCoding.makeDecoder().decode(OutfitLook.self, from: AuthFixtures.json(payload))
        XCTAssertTrue(pending.isStyling)
        XCTAssertNil(pending.styledImageURL)
    }

    func testRemoteImageCacheKeyIgnoresSignedToken() throws {
        let a = try XCTUnwrap(URL(string: "https://cdn.test/storage/v1/object/sign/wardrobe/u/r.jpg?token=one"))
        let b = try XCTUnwrap(URL(string: "https://cdn.test/storage/v1/object/sign/wardrobe/u/r.jpg?token=two"))
        XCTAssertEqual(GMRemoteImage.cacheKey(for: a), GMRemoteImage.cacheKey(for: b))
    }

    func testRemoteImageCacheKeyKeepsMediaVersion() throws {
        let a = try XCTUnwrap(URL(string: "https://cdn.test/storage/v1/object/sign/wardrobe/u/face.jpg?token=one&v=111"))
        let b = try XCTUnwrap(URL(string: "https://cdn.test/storage/v1/object/sign/wardrobe/u/face.jpg?token=two&v=111"))
        let c = try XCTUnwrap(URL(string: "https://cdn.test/storage/v1/object/sign/wardrobe/u/face.jpg?token=two&v=222"))
        XCTAssertEqual(GMRemoteImage.cacheKey(for: a), GMRemoteImage.cacheKey(for: b))
        XCTAssertNotEqual(GMRemoteImage.cacheKey(for: a), GMRemoteImage.cacheKey(for: c))
    }
}
