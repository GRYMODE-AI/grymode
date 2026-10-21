import Foundation

enum OutfitJobStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
}

enum OutfitSlot: String, Codable, Sendable {
    case primary
    case bottom
    case footwear
    case outerwear
    case bag
    case accessory
}

enum AccessPlan: String, Codable, Sendable {
    case free
    case premium
}

struct Entitlement: Codable, Equatable, Sendable {
    let plan: AccessPlan
    let canOpenFullLibrary: Bool
}

struct OutfitGarmentRef: Codable, Identifiable, Equatable, Sendable {
    var id: UUID { garmentId }
    let garmentId: UUID
    let category: GarmentCategory
    let slot: OutfitSlot
    let position: Int
    let imageUrl: String
    let primaryColor: String?
    var subcategory: String? = nil
    var material: String? = nil

    var imageURL: URL? { URL(string: imageUrl) }

    /// "Navy chinos" — what to reach for in the wardrobe to recreate the look.
    var displayName: String {
        let noun = subcategory.flatMap { $0.isEmpty ? nil : $0 } ?? category.title.lowercased()
        let label = [primaryColor, noun].compactMap { $0 }.joined(separator: " ")
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// How the piece is worn in the look.
    var roleTitle: String {
        switch slot {
        case .primary: "Main piece"
        case .bottom: "Bottom"
        case .footwear: "Shoes"
        case .outerwear: "Layer on top"
        case .bag: "Bag"
        case .accessory: "Accessory"
        }
    }
}

enum RenderStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed

    var isInFlight: Bool { self == .pending || self == .running }
}

/// AI-styled image of the whole look, rendered from the user's own garment photos.
struct OutfitVisual: Codable, Equatable, Sendable {
    let status: RenderStatus
    let imageUrl: String?
    let errorCode: String?

    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
}

struct OutfitLook: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let occasionTags: [String]
    let styleTags: [String]
    let contextualTags: [String]
    let score: Double?
    let isFreeReveal: Bool
    let isLocked: Bool
    let isSaved: Bool
    let pieceCount: Int
    let garments: [OutfitGarmentRef]
    let visual: OutfitVisual?
    let createdAt: Date

    init(
        id: UUID,
        title: String,
        occasionTags: [String],
        styleTags: [String],
        contextualTags: [String],
        score: Double?,
        isFreeReveal: Bool,
        isLocked: Bool,
        isSaved: Bool = false,
        pieceCount: Int,
        garments: [OutfitGarmentRef],
        visual: OutfitVisual? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.occasionTags = occasionTags
        self.styleTags = styleTags
        self.contextualTags = contextualTags
        self.score = score
        self.isFreeReveal = isFreeReveal
        self.isLocked = isLocked
        self.isSaved = isSaved
        self.pieceCount = pieceCount
        self.garments = garments
        self.visual = visual
        self.createdAt = createdAt
    }

    var orderedGarments: [OutfitGarmentRef] { garments.sorted(by: { $0.position < $1.position }) }
    var styledImageURL: URL? { visual?.status == .succeeded ? visual?.imageURL : nil }
    var isStyling: Bool { !isLocked && visual?.status.isInFlight == true }

    func withSaved(_ saved: Bool) -> OutfitLook {
        OutfitLook(
            id: id,
            title: title,
            occasionTags: occasionTags,
            styleTags: styleTags,
            contextualTags: contextualTags,
            score: score,
            isFreeReveal: isFreeReveal,
            isLocked: isLocked,
            isSaved: saved,
            pieceCount: pieceCount,
            garments: garments,
            visual: visual,
            createdAt: createdAt
        )
    }
}

struct OutfitJob: Codable, Equatable, Sendable {
    let id: UUID
    let jobType: String
    let status: OutfitJobStatus
    let progressStage: String?
    let errorCode: String?
    let acceptedCount: Int
    let createdAt: Date
    let completedAt: Date?

    var isActive: Bool {
        status == .pending || status == .running
    }
}

struct StartOutfitGenerationResponse: Codable, Equatable, Sendable {
    let job: OutfitJob
    let reusedExisting: Bool
}

struct OutfitLibrary: Codable, Equatable, Sendable {
    let acceptedCount: Int
    let lockedCount: Int
    let savedCount: Int
    let entitlement: Entitlement
    let filterOccasions: [String]
    let outfits: [OutfitLook]
    let activeJob: OutfitJob?

    init(
        acceptedCount: Int,
        lockedCount: Int,
        savedCount: Int = 0,
        entitlement: Entitlement,
        filterOccasions: [String] = [],
        outfits: [OutfitLook],
        activeJob: OutfitJob?
    ) {
        self.acceptedCount = acceptedCount
        self.lockedCount = lockedCount
        self.savedCount = savedCount
        self.entitlement = entitlement
        self.filterOccasions = filterOccasions
        self.outfits = outfits
        self.activeJob = activeJob
    }
}

struct HomeSnapshot: Codable, Equatable, Sendable {
    let todaysLook: OutfitLook?
    let acceptedCount: Int
    let savedCount: Int
    let lockedCount: Int
    let entitlement: Entitlement
    let wardrobeConfirmedCount: Int
}

enum LooksAPI {
    static func generate() -> Endpoint<StartOutfitGenerationResponse> {
        Endpoint(method: .post, path: "/v1/outfits/generate")
    }

    static func job(id: UUID) -> Endpoint<OutfitJob> {
        Endpoint(method: .get, path: "/v1/outfits/jobs/\(id.uuidString.lowercased())")
    }

    static func library(occasion: String? = nil, savedOnly: Bool = false) -> Endpoint<OutfitLibrary> {
        var items: [URLQueryItem] = []
        if let occasion, !occasion.isEmpty {
            items.append(URLQueryItem(name: "occasion", value: occasion))
        }
        if savedOnly {
            items.append(URLQueryItem(name: "saved_only", value: "true"))
        }
        return Endpoint(method: .get, path: "/v1/outfits", queryItems: items)
    }

    static func outfit(id: UUID) -> Endpoint<OutfitLook> {
        Endpoint(method: .get, path: "/v1/outfits/\(id.uuidString.lowercased())")
    }

    static func save(id: UUID) -> Endpoint<OutfitLook> {
        Endpoint(method: .post, path: "/v1/outfits/\(id.uuidString.lowercased())/save")
    }

    static func requestVisual(id: UUID) -> Endpoint<OutfitLook> {
        Endpoint(method: .post, path: "/v1/outfits/\(id.uuidString.lowercased())/visual")
    }

    static func unsave(id: UUID) -> Endpoint<EmptyResponse> {
        Endpoint(method: .delete, path: "/v1/outfits/\(id.uuidString.lowercased())/save")
    }

    static func home() -> Endpoint<HomeSnapshot> {
        Endpoint(method: .get, path: "/v1/home")
    }

    static func entitlement() -> Endpoint<Entitlement> {
        Endpoint(method: .get, path: "/v1/me/entitlement")
    }
}
