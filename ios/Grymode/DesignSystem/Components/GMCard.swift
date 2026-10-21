import SwiftUI

private struct GMCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                    .fill(GMColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                    .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
            )
    }
}

extension View {
    /// Raised paper surface with a hairline border.
    func gmCard(padding: CGFloat = GMSpacing.md) -> some View {
        modifier(GMCardModifier(padding: padding))
    }
}
