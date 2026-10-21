import SwiftUI

/// Editorial header: optional small-caps overline, serif title, optional supporting text.
struct GMSectionHeader: View {
    var overline: String?
    let title: String
    var message: String?
    var titleStyle: GMTextStyle = .title

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xs) {
            if let overline {
                Text(overline)
                    .gmTextStyle(.overline)
                    .foregroundStyle(GMColor.accent)
            }
            Text(title)
                .gmTextStyle(titleStyle)
                .foregroundStyle(GMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .gmTextStyle(.body)
                    .foregroundStyle(GMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
