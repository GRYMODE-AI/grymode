import SwiftUI

struct EmailSignInView: View {
    let model: OnboardingModel
    @FocusState private var isEmailFocused: Bool

    private var signIn: SignInModel { model.signIn }

    var body: some View {
        @Bindable var signIn = model.signIn
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.signIn") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: "Account",
                    title: model.isReturningUser ? "Welcome back" : "Save your style profile",
                    message: model.isReturningUser
                        ? "Enter the email you use with Grymode and we'll send you a 6-digit sign-in code."
                        : "Create your account with your email. We'll send you a 6-digit code, so there's no password to remember."
                )

                GMTextField(label: "Email address", footnote: "We only use your email to sign you in.") {
                    TextField("name@example.com", text: $signIn.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($isEmailFocused)
                        .onSubmit(send)
                        .accessibilityIdentifier("signIn.email")
                }

                if let error = signIn.error {
                    GMInlineError(error: error)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button(action: send) {
                    GMProgressLabel(title: "Send code", isWorking: signIn.isWorking)
                }
                .buttonStyle(.gmPrimary)
                .disabled(!signIn.canSendCode)
                .accessibilityIdentifier("signIn.sendCode")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isEmailFocused = signIn.email.isEmpty }
    }

    private func send() {
        guard signIn.canSendCode else { return }
        Task { await model.sendCode() }
    }
}
