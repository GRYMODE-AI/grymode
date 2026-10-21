import SwiftUI

/// A labelled single-line text field. The label stays visible above the field so it never
/// disappears while typing, and the field grows with Dynamic Type.
struct GMTextField<Field: View>: View {
    let label: String
    var footnote: String?
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xs) {
            Text(label)
                .gmTextStyle(.footnote)
                .foregroundStyle(GMColor.textSecondary)
                .accessibilityHidden(true)
            field()
                .gmTextStyle(.body)
                .foregroundStyle(GMColor.textPrimary)
                .padding(.horizontal, GMSpacing.md)
                .frame(minHeight: GMSize.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                        .fill(GMColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                        .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
                )
                .accessibilityLabel(label)
            if let footnote {
                Text(footnote)
                    .gmTextStyle(.footnote)
                    .foregroundStyle(GMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
