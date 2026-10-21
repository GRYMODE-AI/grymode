import SwiftUI

struct StyleProfileResultView: View {
    let model: OnboardingModel

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.styleResult") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: "Your style profile",
                    title: model.draft.headline,
                    message: model.draft.isEmpty
                        ? "No preferences yet. Grymode will build looks from your wardrobe alone, and you can add preferences any time in Style."
                        : "Grymode uses this to order the looks it creates. Your wardrobe always comes first, and you can change this any time in Style."
                )
                if !model.draft.isEmpty {
                    StyleProfileSummaryCard(profile: model.draft)
                }
                if let error = model.finishError {
                    GMInlineError(error: error)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button {
                    Task { await model.continueFromResult() }
                } label: {
                    GMProgressLabel(title: "Continue", isWorking: model.isFinishing)
                }
                .buttonStyle(.gmPrimary)
                .disabled(model.isFinishing)
                .accessibilityIdentifier("styleResult.continue")
                Button(model.draft.isEmpty ? "Choose preferences" : "Adjust preferences", action: model.editPreferences)
                    .buttonStyle(.gmTertiary)
                    .disabled(model.isFinishing)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
