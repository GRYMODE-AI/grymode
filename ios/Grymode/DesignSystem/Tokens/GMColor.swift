import SwiftUI

/// An sRGB color value that can be reasoned about numerically (for example, contrast checks in tests).
struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    /// WCAG 2.x relative luminance.
    var relativeLuminance: Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// WCAG 2.x contrast ratio, from 1 (none) to 21 (black on white).
    func contrastRatio(against other: RGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Raw brand palette. Screens should use the semantic `GMColor` roles instead of these values.
enum Palette {
    static let softBlack = RGBColor(hex: 0x1A1A1A)
    static let warmOffWhite = RGBColor(hex: 0xF5F3EF)
    static let mutedGrey = RGBColor(hex: 0x8A8A8A)
    static let deepOlive = RGBColor(hex: 0x6B6B4B)

    static let paper = RGBColor(hex: 0xFBFAF7)
    static let stone = RGBColor(hex: 0xECE9E2)
    static let hairline = RGBColor(hex: 0xDCD8CF)
    /// Secondary text. The brand muted grey is too light for body copy on warm off-white (≈3.2:1).
    static let graphite = RGBColor(hex: 0x56564F)
    static let oliveMist = RGBColor(hex: 0xE7E6D6)
    static let oxblood = RGBColor(hex: 0x9A2D2A)
    static let white = RGBColor(hex: 0xFFFFFF)
}

/// Semantic color roles used by every screen.
enum GMColor {
    static var background: Color { Palette.warmOffWhite.color }
    static var surface: Color { Palette.paper.color }
    static var surfaceSunken: Color { Palette.stone.color }
    static var border: Color { Palette.hairline.color }

    static var textPrimary: Color { Palette.softBlack.color }
    static var textSecondary: Color { Palette.graphite.color }
    /// Decorative or disabled content only; does not meet text contrast requirements.
    static var textMuted: Color { Palette.mutedGrey.color }

    static var accent: Color { Palette.deepOlive.color }
    static var accentContainer: Color { Palette.oliveMist.color }

    static var actionPrimary: Color { Palette.softBlack.color }
    static var onActionPrimary: Color { Palette.warmOffWhite.color }

    static var error: Color { Palette.oxblood.color }
}
