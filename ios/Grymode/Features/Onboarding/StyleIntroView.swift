import SwiftUI

struct StyleIntroView: View {
    let model: OnboardingModel

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.styleIntro") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: "Style discovery",
                    title: "Tell us how you like to dress",
                    message:
                        "A few quick choices help Grymode order the looks it creates for you. Every question is optional, and you can change your answers later in Style."
                )

                VStack(alignment: .leading, spacing: GMSpacing.sm) {
                    Label("Three pairs of style tendencies", systemImage: "circle.lefthalf.filled")
                    Label("The occasions you dress for", systemImage: "calendar")
                    Label("The colours you reach for", systemImage: "swatchpalette")
                }
                .gmTextStyle(.callout)
                .foregroundStyle(GMColor.textPrimary)
                .gmCard(padding: GMSpacing.lg)
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button("Choose my preferences", action: model.choosePreferences)
                    .buttonStyle(.gmPrimary)
                    .accessibilityIdentifier("styleIntro.choose")
                Button("Skip for now", action: model.skipPreferences)
                    .buttonStyle(.gmTertiary)
                    .accessibilityIdentifier("styleIntro.skip")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
