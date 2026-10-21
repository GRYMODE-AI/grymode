import Foundation

/// A pair of opposing style tendencies the user can lean towards.
enum StyleAxis: String, CaseIterable, Codable, CodingKeyRepresentable, Identifiable, Sendable {
    case silhouette
    case character
    case finish

    var id: String { rawValue }

    var question: String {
        switch self {
        case .silhouette: "Which silhouette feels more like you?"
        case .character: "Which do you lean towards?"
        case .finish: "How do you like to come across?"
        }
    }

    func label(for pole: StylePole) -> String {
        switch (self, pole) {
        case (.silhouette, .first): "Relaxed"
        case (.silhouette, .second): "Structured"
        case (.character, .first): "Classic"
        case (.character, .second): "Contemporary"
        case (.finish, .first): "Effortless"
        case (.finish, .second): "Refined"
        }
    }
}

enum StylePole: String, CaseIterable, Codable, Sendable {
    case first
    case second
}

enum Occasion: String, CaseIterable, Codable, Identifiable, Sendable {
    case work
    case weekend
    case eveningsOut
    case travel
    case specialOccasions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Work"
        case .weekend: "Weekend"
        case .eveningsOut: "Evenings out"
        case .travel: "Travel"
        case .specialOccasions: "Special occasions"
        }
    }
}

enum PalettePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case neutrals
    case earthTones
    case blackAndWhite
    case colour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutrals: "Neutrals"
        case .earthTones: "Earth tones"
        case .blackAndWhite: "Black & white"
        case .colour: "Colour"
        }
    }
}

/// The user's stated style preferences. Every field is optional; an empty profile is valid.
struct StyleProfile: Codable, Equatable, Sendable {
    var axes: [StyleAxis: StylePole] = [:]
    var occasions: Set<Occasion> = []
    var palettes: Set<PalettePreference> = []

    static let empty = StyleProfile()

    var isEmpty: Bool { axes.isEmpty && occasions.isEmpty && palettes.isEmpty }

    /// Chosen axis labels in a stable order, for example ["Relaxed", "Contemporary"].
    var descriptors: [String] {
        StyleAxis.allCases.compactMap { axis in axes[axis].map { axis.label(for: $0) } }
    }

    var orderedOccasions: [Occasion] { Occasion.allCases.filter(occasions.contains) }
    var orderedPalettes: [PalettePreference] { PalettePreference.allCases.filter(palettes.contains) }

    /// Selecting the active pole again clears the choice.
    mutating func toggle(_ pole: StylePole, on axis: StyleAxis) {
        axes[axis] = axes[axis] == pole ? nil : pole
    }

    mutating func toggle(_ occasion: Occasion) {
        if occasions.contains(occasion) { occasions.remove(occasion) } else { occasions.insert(occasion) }
    }

    mutating func toggle(_ palette: PalettePreference) {
        if palettes.contains(palette) { palettes.remove(palette) } else { palettes.insert(palette) }
    }
}
