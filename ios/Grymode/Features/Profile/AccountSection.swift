import SwiftUI

/// Profile > Account: who is signed in, sign out, and the entry point to account deletion.
struct AccountSection: View {
    let account: AccountModel
    @State private var isConfirmingSignOut = false
    @State private var isSigningOut = false
    @State private var isShowingDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.md) {
            Text("Account")
                .gmTextStyle(.overline)
                .foregroundStyle(GMColor.accent)

            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                Text("Signed in as")
                    .gmTextStyle(.footnote)
                    .foregroundStyle(GMColor.textSecondary)
                Text(account.user?.email ?? "Your Grymode account")
                    .gmTextStyle(.bodyEmphasized)
                    .foregroundStyle(GMColor.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("account.email")
            }
            .accessibilityElement(children: .combine)

            Button {
                isConfirmingSignOut = true
            } label: {
                GMProgressLabel(title: "Sign out", isWorking: isSigningOut)
            }
            .buttonStyle(.gmSecondary)
            .disabled(isSigningOut)
            .accessibilityIdentifier("account.signOut")
            .confirmationDialog("Sign out of Grymode?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    isSigningOut = true
                    Task {
                        await account.signOut()
                        isSigningOut = false
                    }
                }
                .accessibilityIdentifier("account.confirmSignOut")
            } message: {
                Text("Your style profile stays in your account. Sign in again with the same email to get it back.")
            }

            Button {
                isShowingDeletion = true
            } label: {
                Text("Delete account").foregroundStyle(GMColor.error)
            }
            .buttonStyle(.gmTertiary)
            .accessibilityIdentifier("account.delete")
        }
        .gmCard(padding: GMSpacing.lg)
        .sheet(isPresented: $isShowingDeletion) {
            DeleteAccountView(account: account)
        }
    }
}
