import Foundation
import Observation

enum OnboardingStep: Hashable {
    case styleIntro
    case preferences
    case avatar
    case result
    case signIn
    case verifyCode
}

@MainActor
@Observable
final class OnboardingModel {
    var draft: StyleProfile
    var path: [OnboardingStep] = []
    let signIn: SignInModel

    /// Stashed until the account exists (after email verify).
    var pendingHeightCm: Int?
    var pendingBodyBuild: BodyBuild?
    var pendingFaceJPEG: Data?

    private(set) var isFinishing = false
    private(set) var finishError: AppError?

    @ObservationIgnored private let account: AccountModel

    init(store: StyleProfileStore, account: AccountModel) {
        self.account = account
        draft = store.profile
        signIn = SignInModel(account: account)
    }

    var isSignedIn: Bool { account.isSignedIn }
    var accountAPIClient: APIClient? { account.apiClient }

    /// Sign-in screens say "save your profile" after style discovery and "welcome back" otherwise.
    var isReturningUser: Bool { !path.contains(.result) }

    func begin() {
        path.append(.styleIntro)
    }

    func signInFromWelcome() {
        path.append(.signIn)
    }

    func choosePreferences() {
        path.append(.preferences)
    }

    func showAvatarSetup() {
        path.append(.avatar)
    }

    func showResult() {
        path.append(.result)
    }

    /// Skipping keeps nothing the user has not explicitly chosen.
    func skipPreferences() {
        draft = .empty
        path.append(.avatar)
    }

    func editPreferences() {
        if let index = path.lastIndex(of: .preferences) {
            path.removeSubrange((index + 1)...)
        } else {
            path = [.styleIntro, .preferences]
        }
    }

    /// "Continue" on the style result: sign in first, or save straight away if already signed in.
    func continueFromResult() async {
        if account.isSignedIn {
            await finishSignedIn()
        } else {
            finishError = nil
            path.append(.signIn)
        }
    }

    func sendCode() async {
        if await signIn.sendCode(), path.last != .verifyCode {
            path.append(.verifyCode)
        }
    }

    /// Verifies the code (unless already signed in) and then completes onboarding with the account.
    func submitCode() async {
        if !account.isSignedIn {
            finishError = nil
            guard await signIn.verify() else { return }
        }
        await finishSignedIn()
    }

    func useDifferentEmail() {
        signIn.clearError()
        finishError = nil
        if let index = path.lastIndex(of: .signIn) {
            path.removeSubrange((index + 1)...)
        }
    }

    private func finishSignedIn() async {
        guard !isFinishing else { return }
        isFinishing = true
        finishError = nil
        defer { isFinishing = false }
        do throws(AppError) {
            let outcome = try await account.finishSignIn(draft: draft, choseStyle: path.contains(.result))
            try await persistPendingAvatarIfNeeded()
            Log.onboarding.info("Onboarding signed in, preferences set: \(!self.draft.isEmpty, privacy: .public)")
            if outcome == .needsStyleProfile {
                path = [.styleIntro]
            }
        } catch {
            finishError = error
        }
    }

    private func persistPendingAvatarIfNeeded() async throws(AppError) {
        guard let height = pendingHeightCm, let build = pendingBodyBuild else { return }
        let avatar = AvatarModel(api: account.apiClient)
        avatar.draftHeightCm = height
        avatar.draftBuild = build
        guard await avatar.saveMeasurements() else {
            if let error = avatar.actionError { throw error }
            throw .unexpected
        }
        if let jpeg = pendingFaceJPEG {
            guard await avatar.uploadFaceJPEG(jpeg) else {
                if let error = avatar.actionError { throw error }
                throw .unexpected
            }
        }
        pendingFaceJPEG = nil
    }
}
