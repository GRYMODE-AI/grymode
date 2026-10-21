import SwiftUI

/// A horizontal row that gives every item the same width, sized to the widest item's ideal width or
/// stretched to fill the offered space. Subviews marked `.equalWidthRowSeparator()` keep their own width.
///
/// Its ideal width is honest (widest item × count), so inside `ViewThatFits` it is rejected whenever
/// the items would have to wrap or truncate to fit side by side.
struct EqualWidthRow: Layout {
    var spacing: CGFloat = GMSpacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let metrics = measure(subviews)
        let width = max(proposal.width ?? metrics.idealWidth, metrics.idealWidth)
        let itemWidth = itemWidth(forRowWidth: width, metrics: metrics)
        var height: CGFloat = 0
        for index in subviews.indices {
            let proposed = metrics.isSeparator[index] ? nil : itemWidth
            height = max(height, subviews[index].sizeThatFits(ProposedViewSize(width: proposed, height: nil)).height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = measure(subviews)
        let itemWidth = itemWidth(forRowWidth: bounds.width, metrics: metrics)
        var x = bounds.minX
        for index in subviews.indices {
            let width = metrics.isSeparator[index] ? metrics.separatorWidths[index] : itemWidth
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private struct Metrics {
        var isSeparator: [Bool]
        var separatorWidths: [CGFloat]
        var widestItem: CGFloat
        var itemCount: Int
        var fixedWidth: CGFloat

        var idealWidth: CGFloat { widestItem * CGFloat(itemCount) + fixedWidth }
    }

    private func measure(_ subviews: Subviews) -> Metrics {
        let isSeparator = subviews.map { $0[EqualWidthRowSeparatorKey.self] }
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let separatorWidths = subviews.indices.map { isSeparator[$0] ? idealWidths[$0] : 0 }
        let widestItem = subviews.indices.filter { !isSeparator[$0] }.map { idealWidths[$0] }.max() ?? 0
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return Metrics(
            isSeparator: isSeparator,
            separatorWidths: separatorWidths,
            widestItem: widestItem,
            itemCount: isSeparator.filter { !$0 }.count,
            fixedWidth: separatorWidths.reduce(0, +) + gaps
        )
    }

    private func itemWidth(forRowWidth width: CGFloat, metrics: Metrics) -> CGFloat {
        guard metrics.itemCount > 0 else { return 0 }
        return max(0, (width - metrics.fixedWidth) / CGFloat(metrics.itemCount))
    }
}

private struct EqualWidthRowSeparatorKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Marks a view inside `EqualWidthRow` as a separator that keeps its natural width.
    func equalWidthRowSeparator() -> some View {
        layoutValue(key: EqualWidthRowSeparatorKey.self, value: true)
    }
}
