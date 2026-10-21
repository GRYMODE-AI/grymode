import Foundation
import Observation

/// The signed-in account as the UI sees it: session state, profile synchronisation, sign-out,
/// and account deletion.
@MainActor
@Observable
final class AccountModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(AuthUser)
    }

    enum SyncState: Equatable {
        case idle
        case syncing
        case failed(AppError)
    }

    enum SignInOutcome: Equatable {
        /// Onboarding is complete and the app can show the main experience.
        case completed
        /// A new account with no style profile yet; continue onboarding signed in.
        case needsStyleProfile
    }

    private(set) var state: State = .restoring
    private(set) var syncState: SyncState = .idle
    /// Bumped whenever onboarding completion changes so `AppModel.phase` invalidates even when
    /// the nested `StyleProfileStore` update alone would not refresh the root view.
    private(set) var onboardingGeneration = 0

    @ObservationIgnored private let auth: AuthService?
    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored private let styleProfiles: StyleProfileStore
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var presentationChangeHandler: (@MainActor () -> Void)?

    init(auth: AuthService?, api: APIClient?, styleProfiles: StyleProfileStore) {
        self.auth = auth
        self.api = api
        self.styleProfiles = styleProfiles
    }

    /// Called whenever session or onboarding completion changes. Used by `AppModel` to keep a
    /// stored `phase` in sync (nested `@Observable` updates alone are not enough for RootView).
    func onPresentationChange(_ handler: @escaping @MainActor () -> Void) {
        presentationChangeHandler = handler
    }

    var user: AuthUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    var apiClient: APIClient? { api }

    var hasFinishedOnboarding: Bool {
        _ = onboardingGeneration
        return styleProfiles.hasCompletedOnboarding
    }

    /// Restores the previous session, then follows session changes (for example, a refresh the
    /// server rejects) for the rest of the app's life.
    func start() async {
        guard state == .restoring else { return }
        guard let auth else {
            apply(nil)
            return
        }
        apply(await auth.restoreSession())
        let changes = await auth.userChanges()
        observation = Task { [weak self] in
            for await user in changes {
                self?.apply(user)
            }
        }
        await syncStyleProfileIfNeeded()
    }

    // MARK: - Sign-in

    func sendCode(to email: String) async throws(AppError) {
        try await requireAuth().sendCode(to: email)
    }

    func verify(code: String, email: String) async throws(AppError) {
        apply(try await requireAuth().verify(code: code, email: email))
    }

    /// Reconciles the local onboarding draft with the account after sign-in.
    ///
    /// A draft the user just chose wins. If they skipped the questions and the account already has
    /// a profile (a returning user on a new device), the account's profile is kept.
    func finishSignIn(draft: StyleProfile, choseStyle: Bool) async throws(AppError) -> SignInOutcome {
        let api = try requireAPI()
        let remote = try await api.send(AccountAPI.me())
        let accountHasProfile = remote.onboardingCompletedAt != nil

        if choseStyle && (!draft.isEmpty || !accountHasProfile) {
            let saved = try await api.send(AccountAPI.updateStyleProfile(draft, onboardingCompleted: true))
            adopt(saved.styleProfile)
            return .completed
        }
        if accountHasProfile {
            adopt(remote.styleProfile)
            return .completed
        }
        return .needsStyleProfile
    }

    // MARK: - Style profile

    /// Saves locally at once, then uploads. A failed upload stays flagged and is retried.
    func saveStyleProfile(_ profile: StyleProfile) {
        styleProfiles.save(profile)
        Task { await syncStyleProfileIfNeeded() }
    }

    func syncStyleProfileIfNeeded() async {
        guard isSignedIn, styleProfiles.hasCompletedOnboarding, styleProfiles.needsRemoteSync,
            syncState != .syncing, let api
        else { return }

        let profile = styleProfiles.profile
        syncState = .syncing
        do throws(AppError) {
            _ = try await api.send(AccountAPI.updateStyleProfile(profile, onboardingCompleted: true))
            styleProfiles.markSynced(profile)
            syncState = .idle
            if styleProfiles.needsRemoteSync {
                await syncStyleProfileIfNeeded()
            }
        } catch {
            Log.account.error("Style profile upload failed: \(error.apiCode ?? "transport", privacy: .public)")
            syncState = isSignedIn ? .failed(error) : .idle
        }
    }

    // MARK: - Leaving

    func signOut() async {
        await auth?.signOut()
        apply(nil)
    }

    /// Permanently deletes the account on the server, then removes everything stored on device.
    func deleteAccount() async throws(AppError) -> AccountDeletionResult {
        let result = try await requireAPI().send(AccountAPI.deleteAccount())
        Log.account.info("Account deleted")
        await auth?.endSession()
        apply(nil)
        return result
    }

    // MARK: - Private

    private func adopt(_ profile: StyleProfile) {
        styleProfiles.adoptRemote(profile)
        onboardingGeneration &+= 1
        presentationChangeHandler?()
    }

    private func apply(_ user: AuthUser?) {
        if let user {
            state = .signedIn(user)
            presentationChangeHandler?()
            return
        }
        guard state != .signedOut else { return }
        state = .signedOut
        syncState = .idle
        // Style preferences belong to the account; a signed-out device keeps none of them.
        if styleProfiles.hasCompletedOnboarding {
            styleProfiles.reset()
            onboardingGeneration &+= 1
        }
        presentationChangeHandler?()
    }

    private func requireAuth() throws(AppError) -> AuthService {
        guard let auth else { throw .configuration("Sign-in isn't configured for this build.") }
        return auth
    }

    private func requireAPI() throws(AppError) -> APIClient {
        guard let api else { throw .configuration("The Grymode API isn't configured for this build.") }
        return api
    }
}
