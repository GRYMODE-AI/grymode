import SwiftUI

/// Pinned call-to-action area. Attach with `.safeAreaInset(edge: .bottom)` so scroll content is
/// inset above it and the CTA never overlaps content, the keyboard, or the home indicator.
struct GMBottomActionBar<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: GMSpacing.xs) {
            content()
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, horizontalSizeClass == .regular ? GMSpacing.xl : GMSpacing.lg - GMSpacing.xxs)
        .frame(maxWidth: .infinity)
        .padding(.top, GMSpacing.sm)
        .padding(.bottom, GMSpacing.xs)
        .background(
            GMColor.background
                .overlay(alignment: .top) {
                    Rectangle().fill(GMColor.border).frame(height: GMBorder.hairline)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
