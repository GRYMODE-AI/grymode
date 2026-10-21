import SwiftUI

struct OnboardingFlowView: View {
    @State private var model: OnboardingModel

    init(store: StyleProfileStore, account: AccountModel) {
        _model = State(initialValue: OnboardingModel(store: store, account: account))
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(model: model)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .styleIntro: StyleIntroView(model: model)
                    case .preferences: StylePreferencesStepView(model: model)
                    case .avatar: AvatarSetupView(model: model)
                    case .result: StyleProfileResultView(model: model)
                    case .signIn: EmailSignInView(model: model)
                    case .verifyCode: VerifyCodeView(model: model)
                    }
                }
        }
    }
}
