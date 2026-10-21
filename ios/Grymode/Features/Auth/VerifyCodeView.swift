import SwiftUI

struct VerifyCodeView: View {
    let model: OnboardingModel
    @FocusState private var isCodeFocused: Bool

    private var signIn: SignInModel { model.signIn }
    private var isWorking: Bool { signIn.isWorking || model.isFinishing }

    var body: some View {
        @Bindable var signIn = model.signIn
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.verifyCode") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(overline: "Account", title: "Check your email", message: instructions)

                GMTextField(label: "Sign-in code") {
                    TextField("123456", text: $signIn.code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                        .focused($isCodeFocused)
                        .disabled(model.isSignedIn)
                        .accessibilityIdentifier("verify.code")
                }
                .onChange(of: signIn.code) { _, newValue in
                    if newValue.count == SignInModel.codeLength, !isWorking {
                        submit()
                    }
                }

                if let error = signIn.error ?? model.finishError {
                    GMInlineError(error: error)
                }

                if !model.isSignedIn {
                    VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                        ResendButton(signIn: signIn)
                        Button("Use a different email", action: model.useDifferentEmail)
                            .buttonStyle(.gmTertiary)
                            .disabled(isWorking)
                            .accessibilityIdentifier("verify.changeEmail")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button(action: submit) {
                    GMProgressLabel(title: model.isSignedIn ? "Try again" : "Continue", isWorking: isWorking)
                }
                .buttonStyle(.gmPrimary)
                .disabled(isWorking || !(model.isSignedIn || signIn.canVerify))
                .accessibilityIdentifier("verify.submit")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isWorking || model.isSignedIn)
        .onAppear { isCodeFocused = !model.isSignedIn }
    }

    private var instructions: String {
        let address = signIn.sentTo ?? "your email"
        if signIn.isUsingEarlierCode {
            return
                "We emailed a 6-digit code to \(address) less than a minute ago. Enter it if you still have it; if you already used it, wait below to send a new one."
        }
        return "Enter the 6-digit code we sent to \(address). It expires in 10 minutes."
    }

    private func submit() {
        Task { await model.submitCode() }
    }
}

private struct ResendButton: View {
    let signIn: SignInModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = signIn.secondsUntilResend(at: context.date)
            Button(remaining > 0 ? "Send a new code in \(remaining)s" : "Send a new code") {
                Task { await signIn.resendCode() }
            }
            .buttonStyle(.gmTertiary)
            .disabled(remaining > 0 || signIn.isWorking)
            .accessibilityIdentifier("verify.resend")
        }
    }
}
