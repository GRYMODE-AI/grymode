import Foundation

enum BodyBuild: String, Codable, CaseIterable, Sendable, Identifiable {
    case slim
    case regular
    case athletic
    case broad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slim: "Slim"
        case .regular: "Regular"
        case .athletic: "Athletic"
        case .broad: "Broad"
        }
    }
}

struct AvatarProfile: Codable, Equatable, Sendable {
    let heightCm: Int
    let bodyBuild: BodyBuild
    let hasFace: Bool
    let faceUrl: String?
    let updatedAt: Date?

    var faceURL: URL? { faceUrl.flatMap(URL.init(string:)) }
}

struct AvatarFaceUploadSlot: Codable, Equatable, Sendable {
    let objectKey: String
    let uploadUrl: String
    let expiresInSeconds: Int
}

enum TryOnAngle: String, Codable, CaseIterable, Sendable, Identifiable {
    case front
    case threeQuarter = "three_quarter"
    case side
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .threeQuarter: "¾"
        case .side: "Side"
        case .back: "Back"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .front: "Front view"
        case .threeQuarter: "Three-quarter view"
        case .side: "Side view"
        case .back: "Back view"
        }
    }
}

struct TryOnViewRender: Codable, Equatable, Sendable {
    let view: TryOnAngle
    let status: RenderStatus
    let imageUrl: String?
    let errorCode: String?

    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
}

enum TryOnPreviewMode: String, Codable, Sendable {
    /// Face + garment composition when AI rendering isn't configured on the server.
    case personal2D = "personal_2d"
    /// AI renders of the user wearing the look from four angles.
    case aiMultiView = "ai_multi_view"
}

enum TryOnStatus: String, Codable, Sendable {
    case unavailable
    case idle
    case rendering
    case ready
    case partial
    case failed
}

struct TryOnSession: Codable, Equatable, Sendable, Identifiable {
    var id: String { lookId }
    let lookId: String
    let title: String
    let heightCm: Int
    let bodyBuild: BodyBuild
    let faceUrl: String?
    let garmentImageUrls: [String]
    let previewMode: TryOnPreviewMode
    let status: TryOnStatus
    let views: [TryOnViewRender]
    let notice: String

    var faceURL: URL? { faceUrl.flatMap(URL.init(string:)) }
    var garmentURLs: [URL] { garmentImageUrls.compactMap(URL.init(string:)) }

    func render(for angle: TryOnAngle) -> TryOnViewRender? {
        views.first { $0.view == angle }
    }

    var readyCount: Int { views.filter { $0.status == .succeeded && $0.imageURL != nil }.count }
}

enum AvatarAPI {
    static func get() -> Endpoint<AvatarProfile> {
        Endpoint(method: .get, path: "/v1/me/avatar")
    }

    static func upsert(heightCm: Int, bodyBuild: BodyBuild) throws(AppError) -> Endpoint<AvatarProfile> {
        let body = try JSONCoding.encode(UpsertBody(heightCm: heightCm, bodyBuild: bodyBuild))
        return Endpoint(method: .put, path: "/v1/me/avatar", body: body)
    }

    static func faceUploadSlot() -> Endpoint<AvatarFaceUploadSlot> {
        Endpoint(method: .post, path: "/v1/me/avatar/face/upload")
    }

    static func faceComplete() -> Endpoint<AvatarProfile> {
        Endpoint(method: .post, path: "/v1/me/avatar/face/complete")
    }

    static func tryOn(lookId: UUID) -> Endpoint<TryOnSession> {
        Endpoint(method: .get, path: "/v1/try-on/looks/\(lookId.uuidString.lowercased())")
    }

    /// Starts the four-angle render (idempotent; re-renders failed or outdated angles).
    static func startTryOn(lookId: UUID) -> Endpoint<TryOnSession> {
        Endpoint(method: .post, path: "/v1/try-on/looks/\(lookId.uuidString.lowercased())")
    }
}

private struct UpsertBody: Encodable {
    let heightCm: Int
    let bodyBuild: BodyBuild
}
