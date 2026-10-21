import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case style
    case wardrobe
    case looks
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .style: "Style"
        case .wardrobe: "Wardrobe"
        case .looks: "Looks"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .style: "paintpalette"
        case .wardrobe: "hanger"
        case .looks: "square.grid.2x2"
        case .profile: "person.crop.circle"
        }
    }
}
