import SwiftUI

/// Editable style preferences. Shared by onboarding and the Style tab editor.
struct StylePreferencesForm: View {
    @Binding var profile: StyleProfile
    @ScaledMetric(relativeTo: .callout) private var minimumChipWidth: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xl) {
            ForEach(StyleAxis.allCases) { axis in
                AxisQuestion(axis: axis, selection: profile.axes[axis]) { pole in
                    profile.toggle(pole, on: axis)
                }
            }

            MultiChoiceQuestion(
                title: "What do you dress for most?",
                hint: "Choose any that apply.",
                options: Occasion.allCases,
                label: \.title,
                isSelected: { profile.occasions.contains($0) },
                toggle: { profile.toggle($0) },
                minimumChipWidth: minimumChipWidth
            )

            MultiChoiceQuestion(
                title: "Which colours do you reach for?",
                hint: "Choose any that apply.",
                options: PalettePreference.allCases,
                label: \.title,
                isSelected: { profile.palettes.contains($0) },
                toggle: { profile.toggle($0) },
                minimumChipWidth: minimumChipWidth
            )
        }
    }
}

private struct AxisQuestion: View {
    let axis: StyleAxis
    let selection: StylePole?
    let select: (StylePole) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.sm) {
            Text(axis.question)
                .gmTextStyle(.subheadline)
                .foregroundStyle(GMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                EqualWidthRow(spacing: GMSpacing.sm) { chips(separator: true) }
                VStack(spacing: GMSpacing.xs) { chips(separator: false) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chips(separator: Bool) -> some View {
        chip(.first)
        if separator {
            Text("or")
                .gmTextStyle(.caption)
                .foregroundStyle(GMColor.textSecondary)
                .accessibilityHidden(true)
                .equalWidthRowSeparator()
        }
        chip(.second)
    }

    private func chip(_ pole: StylePole) -> some View {
        GMChoiceChip(title: axis.label(for: pole), isSelected: selection == pole) {
            select(pole)
        }
        .accessibilityIdentifier("preference.\(axis.rawValue).\(pole.rawValue)")
    }
}

private struct MultiChoiceQuestion<Option: Identifiable & Hashable>: View {
    let title: String
    let hint: String
    let options: [Option]
    let label: KeyPath<Option, String>
    let isSelected: (Option) -> Bool
    let toggle: (Option) -> Void
    let minimumChipWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.sm) {
            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                Text(title)
                    .gmTextStyle(.subheadline)
                    .foregroundStyle(GMColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(hint)
                    .gmTextStyle(.footnote)
                    .foregroundStyle(GMColor.textSecondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimumChipWidth), spacing: GMSpacing.sm)],
                alignment: .leading,
                spacing: GMSpacing.sm
            ) {
                ForEach(options) { option in
                    GMChoiceChip(title: option[keyPath: label], isSelected: isSelected(option)) {
                        toggle(option)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
