import SwiftUI

struct StylePreferencesStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.preferences") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: "Style discovery",
                    title: "Your preferences",
                    message: "Tap a choice again to clear it.",
                    titleStyle: .headline
                )
                StylePreferencesForm(profile: $model.draft)
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button("Continue", action: model.showAvatarSetup)
                    .buttonStyle(.gmPrimary)
                    .accessibilityIdentifier("preferences.continue")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: model.skipPreferences)
                    .accessibilityIdentifier("preferences.skip")
            }
        }
    }
}
