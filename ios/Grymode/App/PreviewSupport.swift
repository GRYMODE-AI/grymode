#if DEBUG
    import Foundation

    extension StyleProfileStore {
        /// Isolated, throwaway storage for SwiftUI previews.
        static func preview(profile: StyleProfile = .empty, completedOnboarding: Bool = false) -> StyleProfileStore {
            let suiteName = "preview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let store = StyleProfileStore(defaults: defaults)
            if completedOnboarding {
                store.completeOnboarding(with: profile)
            } else if profile != .empty {
                store.save(profile)
            }
            return store
        }
    }

    /// Keeps sessions in memory so previews and tests never touch the Keychain.
    final class EphemeralSessionStore: SessionStore, @unchecked Sendable {
        private let lock = NSLock()
        private var session: AuthSession?

        init(session: AuthSession? = nil) {
            self.session = session
        }

        func load() -> AuthSession? {
            lock.withLock { session }
        }

        func save(_ session: AuthSession) throws(AppError) {
            lock.withLock { self.session = session }
        }

        func clear() {
            lock.withLock { session = nil }
        }
    }

    extension AppModel {
        static func preview() -> AppModel {
            let fallbackURL = URL(fileURLWithPath: "/")
            let configuration = AppConfiguration(
                environment: .development,
                apiBaseURL: URL(string: "http://127.0.0.1:8000") ?? fallbackURL,
                supabaseURL: URL(string: "http://127.0.0.1:54321") ?? fallbackURL,
                supabasePublishableKey: "preview"
            )
            let styleProfiles = StyleProfileStore.preview(completedOnboarding: true)
            return AppModel(
                configuration: .success(configuration),
                apiClient: nil,
                styleProfiles: styleProfiles,
                account: AccountModel(auth: nil, api: nil, styleProfiles: styleProfiles)
            )
        }
    }

    extension OnboardingModel {
        static func preview() -> OnboardingModel {
            let store = StyleProfileStore.preview()
            return OnboardingModel(store: store, account: AccountModel(auth: nil, api: nil, styleProfiles: store))
        }
    }
#endif
