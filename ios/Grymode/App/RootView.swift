import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView()
            case .onboarding:
                OnboardingFlowView(store: model.styleProfiles, account: model.account)
                    .transition(.opacity)
            case .main:
                MainShellView(router: model.router)
                    .transition(.opacity)
            }
        }
        .animation(GMMotion.standard, value: model.phase)
        .tint(GMColor.textPrimary)
        .task {
            model.subscriptions.startListeningForTransactions()
            await model.account.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.account.syncStyleProfileIfNeeded()
                    if case .signedIn = model.account.state {
                        await model.subscriptions.syncCurrentEntitlements()
                    }
                }
            }
        }
    }
}

/// Shown for the moment it takes to read the saved session from the Keychain.
private struct LaunchView: View {
    var body: some View {
        VStack(spacing: GMSpacing.lg) {
            GMWordmark()
            ProgressView()
                .tint(GMColor.accent)
                .accessibilityLabel("Loading")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GMColor.background)
        .accessibilityIdentifier("screen.launch")
    }
}
