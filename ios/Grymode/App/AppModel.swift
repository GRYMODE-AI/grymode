import Foundation
import Observation

/// Composition root: owns long-lived services and decides which top-level experience to show.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case onboarding
        case main
    }

    static let resetStateLaunchArgument = "-uiTestingResetState"

    let configuration: Result<AppConfiguration, AppError>
    let apiClient: APIClient?
    let router: AppRouter
    let styleProfiles: StyleProfileStore
    let account: AccountModel
    let subscriptions: SubscriptionStore
    /// Stored (not computed) so assigning it always invalidates `RootView`.
    private(set) var phase: Phase

    init(
        configuration: Result<AppConfiguration, AppError>,
        apiClient: APIClient?,
        router: AppRouter = AppRouter(),
        styleProfiles: StyleProfileStore,
        account: AccountModel,
        subscriptions: SubscriptionStore = SubscriptionStore()
    ) {
        self.configuration = configuration
        self.apiClient = apiClient
        self.router = router
        self.styleProfiles = styleProfiles
        self.account = account
        self.subscriptions = subscriptions
        self.phase = Self.phase(for: account)
        subscriptions.bind(api: apiClient)
        account.onPresentationChange { [weak self] in
            self?.refreshPhase()
        }
    }

    private func refreshPhase() {
        let next = Self.phase(for: account)
        guard phase != next else { return }
        if next == .onboarding { router.resetToHome() }
        phase = next
    }

    private static func phase(for account: AccountModel) -> Phase {
        switch account.state {
        case .restoring: .launching
        case .signedOut: .onboarding
        case .signedIn: account.hasFinishedOnboarding ? .main : .onboarding
        }
    }

    static func live(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main) -> AppModel {
        let defaults = UserDefaults.standard
        let bundleID = bundle.bundleIdentifier ?? "com.grymode.stylist"
        let sessionStore = KeychainSessionStore(service: "\(bundleID).auth")
        if processInfo.arguments.contains(resetStateLaunchArgument) {
            defaults.removePersistentDomain(forName: bundleID)
            sessionStore.clear()
        }

        let configuration = Result { () throws(AppError) in try AppConfiguration.load(from: bundle) }
        if case .failure(let error) = configuration {
            Log.app.error("Configuration error: \(error.userMessage, privacy: .public)")
        }

        let transport = URLSessionTransport.makeDefault()
        let auth = (try? configuration.get()).map { config in
            AuthService(
                client: SupabaseAuthClient(
                    baseURL: config.supabaseURL,
                    publishableKey: config.supabasePublishableKey,
                    transport: transport
                ),
                store: sessionStore
            )
        }
        let apiClient = (try? configuration.get()).map { config in
            APIClient(
                builder: RequestBuilder(baseURL: config.apiBaseURL, clientVersion: bundle.versionDescription),
                transport: transport,
                tokens: auth ?? SignedOutTokenProvider()
            )
        }

        let styleProfiles = StyleProfileStore(defaults: defaults)
        return AppModel(
            configuration: configuration,
            apiClient: apiClient,
            styleProfiles: styleProfiles,
            account: AccountModel(auth: auth, api: apiClient, styleProfiles: styleProfiles)
        )
    }
}

extension Bundle {
    /// "0.1.0 (1)"
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
