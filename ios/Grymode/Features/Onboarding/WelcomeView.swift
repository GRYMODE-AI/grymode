import SwiftUI

struct WelcomeView: View {
    let model: OnboardingModel

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.welcome") { layout in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMWordmark()
                    .padding(.top, layout.widthClass == .compact ? GMSpacing.md : GMSpacing.xxl)

                VStack(alignment: .leading, spacing: GMSpacing.md) {
                    Text("Your wardrobe has more to say.")
                        .gmTextStyle(.display)
                        .foregroundStyle(GMColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "Grymode finds new ways to wear the clothes you already own. Add your wardrobe and we'll build a personal library of complete outfits from it."
                    )
                    .gmTextStyle(.body)
                    .foregroundStyle(GMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: GMSpacing.lg) {
                    WelcomeStepRow(
                        number: 1,
                        title: "Capture your clothes",
                        message: "Upload photos or a short video of your wardrobe."
                    )
                    WelcomeStepRow(
                        number: 2,
                        title: "Confirm your pieces",
                        message: "Review what we found and correct anything we got wrong."
                    )
                    WelcomeStepRow(
                        number: 3,
                        title: "Discover your looks",
                        message: "Get complete outfits made only from what you own."
                    )
                }
                .gmCard(padding: GMSpacing.lg)

                Label("Your wardrobe photos are private to your account.", systemImage: "lock")
                    .gmTextStyle(.footnote)
                    .foregroundStyle(GMColor.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button("Get started", action: model.begin)
                    .buttonStyle(.gmPrimary)
                    .accessibilityIdentifier("welcome.getStarted")
                if !model.isSignedIn {
                    Button("I already have an account", action: model.signInFromWelcome)
                        .buttonStyle(.gmTertiary)
                        .accessibilityIdentifier("welcome.signIn")
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct WelcomeStepRow: View {
    let number: Int
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GMSpacing.md) {
            Text("\(number)")
                .gmTextStyle(.subheadline)
                .foregroundStyle(GMColor.accent)
                .frame(minWidth: GMSpacing.lg, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                Text(title)
                    .gmTextStyle(.bodyEmphasized)
                    .foregroundStyle(GMColor.textPrimary)
                Text(message)
                    .gmTextStyle(.callout)
                    .foregroundStyle(GMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(message)")
    }
}

#Preview("iPhone") {
    WelcomeView(model: .preview())
}

#Preview("iPad landscape", traits: .fixedLayout(width: 1180, height: 820)) {
    WelcomeView(model: .preview())
}
