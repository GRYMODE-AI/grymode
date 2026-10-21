import SwiftUI

struct StyleView: View {
    @Environment(AppModel.self) private var model
    @State private var isEditing = false

    var body: some View {
        let profile = model.styleProfiles.profile
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.style") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: "Your style profile",
                    title: profile.headline,
                    message: profile.isEmpty
                        ? "You haven't set any preferences. Grymode will rely on your wardrobe alone."
                        : "Grymode uses these preferences to order the looks it creates from your wardrobe."
                )
                if !profile.isEmpty {
                    StyleProfileSummaryCard(profile: profile)
                }
                if case .failed(let error) = model.account.syncState {
                    VStack(alignment: .leading, spacing: GMSpacing.xs) {
                        Text("Your latest changes are saved on this device but not yet in your account.")
                            .gmTextStyle(.callout)
                            .foregroundStyle(GMColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        GMInlineError(error: error)
                        Button("Try again") {
                            Task { await model.account.syncStyleProfileIfNeeded() }
                        }
                        .buttonStyle(.gmSecondary)
                        .accessibilityIdentifier("style.retrySync")
                    }
                }
                Button(profile.isEmpty ? "Choose preferences" : "Edit preferences") {
                    isEditing = true
                }
                .buttonStyle(.gmPrimary)
                .accessibilityIdentifier("style.edit")
            }
        }
        .sheet(isPresented: $isEditing) {
            StylePreferencesEditor(initialProfile: profile) { updated in
                model.account.saveStyleProfile(updated)
            }
        }
    }
}

private struct StylePreferencesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StyleProfile
    private let initialProfile: StyleProfile
    private let onSave: (StyleProfile) -> Void

    init(initialProfile: StyleProfile, onSave: @escaping (StyleProfile) -> Void) {
        self.initialProfile = initialProfile
        self.onSave = onSave
        _draft = State(initialValue: initialProfile)
    }

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(accessibilityIdentifier: "screen.styleEditor") { _ in
                StylePreferencesForm(profile: $draft)
            }
            .navigationTitle("Edit preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft == initialProfile)
                    .accessibilityIdentifier("styleEditor.save")
                }
            }
        }
        .interactiveDismissDisabled(draft != initialProfile)
    }
}
