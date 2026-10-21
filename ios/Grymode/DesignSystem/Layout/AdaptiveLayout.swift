import SwiftUI

/// Layout decisions derived from the space a screen actually has, never from a device model.
struct AdaptiveLayout: Equatable, Sendable {
    enum WidthClass: Equatable, Sendable {
        /// Phones in portrait, iPad Slide Over and narrow Split View.
        case compact
        /// Large phones in landscape, iPad portrait and half-screen Split View.
        case regular
        /// iPad landscape full screen and large windows.
        case expanded
    }

    static let regularBreakpoint: CGFloat = 600
    static let expandedBreakpoint: CGFloat = 960

    let containerWidth: CGFloat
    let widthClass: WidthClass

    init(containerWidth: CGFloat) {
        self.containerWidth = max(0, containerWidth)
        switch self.containerWidth {
        case ..<Self.regularBreakpoint: widthClass = .compact
        case ..<Self.expandedBreakpoint: widthClass = .regular
        default: widthClass = .expanded
        }
    }

    var horizontalMargin: CGFloat {
        switch widthClass {
        case .compact: GMSpacing.lg - GMSpacing.xxs
        case .regular: GMSpacing.xl
        case .expanded: GMSpacing.xxl
        }
    }

    /// Maximum width for reading-oriented content so lines stay comfortable on large screens.
    var readableContentWidth: CGFloat {
        switch widthClass {
        case .compact: .infinity
        case .regular: 680
        case .expanded: 760
        }
    }

    /// Maximum width for grid-oriented content (wardrobe, looks), which can use more space.
    var gridContentWidth: CGFloat { 1180 }

    /// Column count for wardrobe and look grids given the usable width.
    var gridColumnCount: Int {
        let usable = min(containerWidth, gridContentWidth) - horizontalMargin * 2
        let minimumCellWidth: CGFloat = 150
        return max(2, min(6, Int(usable / minimumCellWidth)))
    }

    /// Whether a two-pane editorial layout (image beside text) fits comfortably.
    var prefersSideBySide: Bool { widthClass != .compact }
}
