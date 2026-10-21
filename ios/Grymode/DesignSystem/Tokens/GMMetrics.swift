import SwiftUI

enum GMSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
}

enum GMRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum GMBorder {
    static let hairline: CGFloat = 1
    static let emphasis: CGFloat = 1.5
}

enum GMSize {
    /// Apple's minimum comfortable hit target.
    static let minTapTarget: CGFloat = 44
    static let buttonHeight: CGFloat = 52
    static let iconSmall: CGFloat = 16
    static let iconMedium: CGFloat = 22
    static let iconLarge: CGFloat = 32
}

enum GMMotion {
    static var standard: Animation { .easeInOut(duration: 0.25) }
    static var emphasized: Animation { .spring(response: 0.4, dampingFraction: 0.85) }
}

private struct GMShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Palette.softBlack.color.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

extension View {
    /// The single restrained elevation used across the app.
    func gmShadow() -> some View {
        modifier(GMShadowModifier())
    }
}
