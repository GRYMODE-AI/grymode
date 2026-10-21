import SwiftUI

/// Explains what account deletion does, requires explicit confirmation, and performs it.
/// On success the account model signs out and the app returns to the welcome screen.
struct DeleteAccountView: View {
    let account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isConfirming = false
    @State private var isDeleting = false
    @State private var error: AppError?

    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(accessibilityIdentifier: "screen.deleteAccount") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.xl) {
                    GMSectionHeader(
                        overline: "Account",
                        title: "Delete your account",
                        message: "This permanently deletes your Grymode account. It can't be undone."
                    )

                    VStack(alignment: .leading, spacing: GMSpacing.sm) {
                        Text("What will be deleted")
                            .gmTextStyle(.bodyEmphasized)
                            .foregroundStyle(GMColor.textPrimary)
                        Label("Your account and sign-in details", systemImage: "person.crop.circle")
                        Label("Your style profile and preferences", systemImage: "circle.lefthalf.filled")
                        Label("Everything else you've added to Grymode", systemImage: "tray")
                    }
                    .gmTextStyle(.callout)
                    .foregroundStyle(GMColor.textPrimary)
                    .gmCard(padding: GMSpacing.lg)

                    VStack(alignment: .leading, spacing: GMSpacing.sm) {
                        Text("Your subscription isn't cancelled automatically")
                            .gmTextStyle(.bodyEmphasized)
                            .foregroundStyle(GMColor.textPrimary)
                        Text(
                            "Deleting your account does not cancel an App Store subscription. To stop being charged, cancel it in Settings > your name > Subscriptions."
                        )
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        if let url = Self.manageSubscriptionsURL {
                            Button("Manage subscriptions") { openURL(url) }
                                .buttonStyle(.gmSecondary)
                                .accessibilityIdentifier("deleteAccount.manageSubscriptions")
                        }
                    }
                    .gmCard(padding: GMSpacing.lg)

                    if let error {
                        GMInlineError(error: error)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                GMBottomActionBar {
                    Button {
                        isConfirming = true
                    } label: {
                        GMProgressLabel(title: "Delete account", isWorking: isDeleting)
                    }
                    .buttonStyle(.gmDestructive)
                    .disabled(isDeleting)
                    .accessibilityIdentifier("deleteAccount.delete")
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .confirmationDialog(
                "Permanently delete your account?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive, action: delete)
                    .accessibilityIdentifier("deleteAccount.confirm")
            } message: {
                Text("Your account and everything in it will be deleted. This can't be undone.")
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func delete() {
        isDeleting = true
        error = nil
        Task {
            do throws(AppError) {
                _ = try await account.deleteAccount()
            } catch {
                self.error = error
            }
            isDeleting = false
        }
    }
}
