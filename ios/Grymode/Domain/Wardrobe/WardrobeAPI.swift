import Foundation

enum WardrobeMediaType: String, Codable, Sendable {
    case photo
    case videoFrame = "video_frame"
}

enum MediaProcessingStatus: String, Codable, Sendable {
    case awaitingUpload = "awaiting_upload"
    case uploaded
    case processing
    case ready
    case failed
}

enum GarmentCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case tops
    case bottoms
    case dresses
    case outerwear
    case shoes
    case bags
    case accessories
    case knitwear
    case activewear
    case uncategorised

    var id: String { rawValue }

    /// Categories the user can assign when labelling a draft piece.
    static var labelChoices: [GarmentCategory] {
        allCases.filter { $0 != .uncategorised }
    }

    var title: String {
        switch self {
        case .tops: "Tops"
        case .bottoms: "Bottoms"
        case .dresses: "Dresses"
        case .outerwear: "Outerwear"
        case .shoes: "Shoes"
        case .bags: "Bags"
        case .accessories: "Accessories"
        case .knitwear: "Knitwear"
        case .activewear: "Activewear"
        case .uncategorised: "Needs a label"
        }
    }
}

enum GarmentFormality: String, Codable, Sendable {
    case casual
    case smartCasual
    case formal

    var title: String {
        switch self {
        case .casual: "Casual"
        case .smartCasual: "Smart casual"
        case .formal: "Formal"
        }
    }
}

enum WardrobeJobStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
}

struct UploadSlotResponse: Decodable, Equatable, Sendable {
    let mediaId: UUID
    let objectKey: String
    let uploadUrl: String
    let expiresInSeconds: Int
    let jobId: UUID?
}

struct CompleteUploadResponse: Decodable, Equatable, Sendable {
    let mediaId: UUID
    let processingStatus: MediaProcessingStatus
    let jobId: UUID
}

struct WardrobeMedia: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let mediaType: WardrobeMediaType
    let contentType: String
    let processingStatus: MediaProcessingStatus
    let createdAt: Date
}

struct WardrobeJob: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let mediaId: UUID?
    let jobType: String
    let status: WardrobeJobStatus
    let progressStage: String?
    let errorCode: String?
    let createdAt: Date
    let completedAt: Date?
}

struct WardrobeGarment: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let mediaId: UUID?
    let category: GarmentCategory
    let subcategory: String?
    let primaryColor: String?
    let secondaryColors: [String]
    let pattern: String?
    let material: String?
    let silhouette: String?
    let formality: GarmentFormality?
    let seasonTags: [String]
    let styleTags: [String]
    let imageUrl: String
    let confidence: Double?
    let userConfirmed: Bool
    let createdAt: Date
    let updatedAt: Date

    var needsLabel: Bool { category == .uncategorised }
    var isReadyToConfirm: Bool { !userConfirmed && !needsLabel }

    /// Short human name such as "Navy blazer"; falls back to the category.
    var displayName: String {
        let words = [primaryColor, subcategory].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty, !needsLabel else { return category.title }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    /// Details proposed by Grymode's vision step, in display order.
    var detectedDetails: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let subcategory, !subcategory.isEmpty { rows.append(("Type", subcategory)) }
        let colours = ([primaryColor].compactMap { $0 } + secondaryColors).filter { !$0.isEmpty }
        if !colours.isEmpty { rows.append(("Colour", colours.joined(separator: ", "))) }
        if let material, !material.isEmpty { rows.append(("Material", material)) }
        if let pattern, !pattern.isEmpty { rows.append(("Pattern", pattern)) }
        if let formality { rows.append(("Formality", formality.title)) }
        if !seasonTags.isEmpty { rows.append(("Seasons", seasonTags.joined(separator: ", "))) }
        return rows
    }
}

struct WardrobeSummary: Decodable, Equatable, Sendable {
    var media: [WardrobeMedia]
    var garments: [WardrobeGarment]
    var jobs: [WardrobeJob]
    var unconfirmedCount: Int
    var confirmedCount: Int
}

struct ConfirmWardrobeResponse: Decodable, Equatable, Sendable {
    let confirmedCount: Int
}

enum WardrobeAPI {
    static func createUpload(
        mediaType: WardrobeMediaType,
        contentType: String,
        byteSize: Int,
        clientUploadId: UUID
    ) throws(AppError) -> Endpoint<UploadSlotResponse> {
        let body = try JSONCoding.encode(
            CreateUploadBody(
                mediaType: mediaType,
                contentType: contentType,
                byteSize: byteSize,
                clientUploadId: clientUploadId
            )
        )
        return Endpoint(
            method: .post,
            path: "/v1/wardrobe/uploads",
            body: body,
            idempotencyKey: clientUploadId.uuidString.lowercased()
        )
    }

    static func completeUpload(mediaId: UUID) -> Endpoint<CompleteUploadResponse> {
        Endpoint(
            method: .post,
            path: "/v1/wardrobe/uploads/\(mediaId.uuidString.lowercased())/complete",
            idempotencyKey: mediaId.uuidString.lowercased()
        )
    }

    static func summary() -> Endpoint<WardrobeSummary> {
        Endpoint(method: .get, path: "/v1/wardrobe")
    }

    static func updateGarment(
        id: UUID,
        category: GarmentCategory? = nil,
        primaryColor: String? = nil
    ) throws(AppError) -> Endpoint<WardrobeGarment> {
        let body = try JSONCoding.encode(UpdateGarmentBody(category: category, primaryColor: primaryColor))
        return Endpoint(method: .patch, path: "/v1/wardrobe/garments/\(id.uuidString.lowercased())", body: body)
    }

    static func deleteGarment(id: UUID) -> Endpoint<EmptyResponse> {
        Endpoint(method: .delete, path: "/v1/wardrobe/garments/\(id.uuidString.lowercased())")
    }

    static func confirm(garmentIds: [UUID]?) throws(AppError) -> Endpoint<ConfirmWardrobeResponse> {
        let key = UUID().uuidString.lowercased()
        let body = try JSONCoding.encode(ConfirmBody(garmentIds: garmentIds))
        return Endpoint(method: .post, path: "/v1/wardrobe/confirm", body: body, idempotencyKey: key)
    }
}

private struct CreateUploadBody: Encodable {
    let mediaType: WardrobeMediaType
    let contentType: String
    let byteSize: Int
    let clientUploadId: UUID
}

private struct UpdateGarmentBody: Encodable {
    let category: GarmentCategory?
    let primaryColor: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(primaryColor, forKey: .primaryColor)
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case primaryColor
    }
}

private struct ConfirmBody: Encodable {
    let garmentIds: [UUID]?
}
