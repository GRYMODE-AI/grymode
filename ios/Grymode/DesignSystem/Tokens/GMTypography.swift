import SwiftUI

/// Bundled typefaces (SIL Open Font License, see docs/licenses).
enum GMTypeface {
    static let display = "Oranienbaum-Regular"
    static let heading = "Unna-Regular"
    static let headingItalic = "Unna-Italic"
    static let headingBold = "Unna-Bold"
}

/// Every text style in the app. Custom faces scale with Dynamic Type via `relativeTo:`;
/// body and control text use the system font for legibility and accessibility.
enum GMTextStyle: CaseIterable {
    case display
    case title
    case headline
    case subheadline
    case body
    case bodyEmphasized
    case callout
    case footnote
    case caption
    case overline
    case button
    case wordmark

    var font: Font {
        switch self {
        case .wordmark: .custom(GMTypeface.heading, size: 17, relativeTo: .headline)
        case .display: .custom(GMTypeface.display, size: 38, relativeTo: .largeTitle)
        case .title: .custom(GMTypeface.display, size: 30, relativeTo: .title)
        case .headline: .custom(GMTypeface.heading, size: 22, relativeTo: .title2)
        case .subheadline: .custom(GMTypeface.heading, size: 18, relativeTo: .title3)
        case .body: .body
        case .bodyEmphasized: .body.weight(.medium)
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption
        case .overline: .caption2.weight(.semibold)
        case .button: .body.weight(.medium)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display, .title: -0.3
        case .overline: 1.4
        case .wordmark: 3
        default: 0
        }
    }

    var isUppercased: Bool { self == .overline || self == .wordmark }
}

private struct GMTextStyleModifier: ViewModifier {
    let style: GMTextStyle

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

extension View {
    func gmTextStyle(_ style: GMTextStyle) -> some View {
        modifier(GMTextStyleModifier(style: style))
    }
}
