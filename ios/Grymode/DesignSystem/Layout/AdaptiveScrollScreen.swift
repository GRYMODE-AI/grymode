import SwiftUI

/// Standard scrolling screen container: warm background, adaptive margins, and a width cap so
/// content never stretches edge to edge on iPad. Content always scrolls, so nothing clips at
/// large Dynamic Type sizes or short viewports.
struct AdaptiveScrollScreen<Content: View>: View {
    enum ContentWidth {
        case readable
        case grid
    }

    var contentWidth: ContentWidth = .readable
    var accessibilityIdentifier: String?
    @ViewBuilder let content: (AdaptiveLayout) -> Content

    var body: some View {
        GeometryReader { proxy in
            let layout = AdaptiveLayout(containerWidth: proxy.size.width)
            ScrollView {
                content(layout)
                    .frame(
                        maxWidth: contentWidth == .readable ? layout.readableContentWidth : layout.gridContentWidth,
                        alignment: .leading
                    )
                    .padding(.horizontal, layout.horizontalMargin)
                    .padding(.vertical, GMSpacing.lg)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
        .background(GMColor.background.ignoresSafeArea())
    }
}
