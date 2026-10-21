import SwiftUI

/// Selectable pill used for style preferences and filters.
struct GMChoiceChip: View {
    let title: String
    let isSelected: Bool
    /// When false, the chip sizes to its label (horizontal filter bars). Default expands for grids.
    var expands: Bool = true
    let action: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var checkmarkWidth: CGFloat = 13

    var body: some View {
        Button(action: action) {
            // Symmetric padding wide enough for the checkmark keeps the label centred and the chip's
            // width unchanged when it is selected.
            Text(title)
                .gmTextStyle(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, checkmarkWidth + GMSpacing.xxs)
                .frame(maxWidth: expands ? .infinity : nil)
                .overlay(alignment: .leading) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: checkmarkWidth)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(isSelected ? GMColor.onActionPrimary : GMColor.textPrimary)
                .padding(.horizontal, GMSpacing.sm)
                .padding(.vertical, GMSpacing.xs)
                .frame(minHeight: GMSize.minTapTarget)
                .background(
                    Capsule().fill(isSelected ? GMColor.actionPrimary : GMColor.surface)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : GMColor.border, lineWidth: GMBorder.hairline)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(GMMotion.standard, value: isSelected)
    }
}
