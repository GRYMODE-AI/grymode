import SwiftUI

extension StyleProfile {
    /// Editorial headline for the profile, e.g. "Relaxed · Contemporary · Refined".
    var headline: String {
        descriptors.isEmpty ? "Open to everything" : descriptors.joined(separator: " · ")
    }
}

struct StyleProfileSummaryCard: View {
    let profile: StyleProfile

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.md) {
            SummaryRow(title: "Leaning towards", value: profile.descriptors.joined(separator: ", "))
            SummaryRow(title: "Dressing for", value: profile.orderedOccasions.map(\.title).joined(separator: ", "))
            SummaryRow(title: "Colours", value: profile.orderedPalettes.map(\.title).joined(separator: ", "))
        }
        .gmCard(padding: GMSpacing.lg)
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xxs) {
            Text(title)
                .gmTextStyle(.overline)
                .foregroundStyle(GMColor.accent)
            Text(value.isEmpty ? "Not specified" : value)
                .gmTextStyle(.body)
                .foregroundStyle(value.isEmpty ? GMColor.textSecondary : GMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
