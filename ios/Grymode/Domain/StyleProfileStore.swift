import Foundation
import Observation

/// Persists the style profile and onboarding completion on device.
///
/// The backend is the source of truth once the user is signed in. Local edits are saved here
/// first and flagged until `AccountModel` has uploaded them, so nothing is lost offline.
@MainActor
@Observable
final class StyleProfileStore {
    enum Key {
        static let profile = "styleProfile.v1"
        static let onboardingCompleted = "onboardingCompleted.v1"
        static let needsRemoteSync = "styleProfile.needsRemoteSync.v1"
    }

    private(set) var profile: StyleProfile
    private(set) var hasCompletedOnboarding: Bool
    private(set) var needsRemoteSync: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingCompleted)
        needsRemoteSync = defaults.bool(forKey: Key.needsRemoteSync)
        if let data = defaults.data(forKey: Key.profile),
            let stored = try? JSONDecoder().decode(StyleProfile.self, from: data)
        {
            profile = stored
        } else {
            profile = .empty
        }
    }

    /// Saves a local edit and marks it for upload.
    func save(_ profile: StyleProfile) {
        store(profile)
        setNeedsRemoteSync(true)
    }

    func completeOnboarding(with profile: StyleProfile) {
        save(profile)
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Key.onboardingCompleted)
    }

    /// Replaces local state with the profile the server holds.
    func adoptRemote(_ profile: StyleProfile) {
        store(profile)
        setNeedsRemoteSync(false)
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Key.onboardingCompleted)
    }

    /// Clears the upload flag, but only if `uploaded` is still the current profile.
    func markSynced(_ uploaded: StyleProfile) {
        if uploaded == profile { setNeedsRemoteSync(false) }
    }

    func reset() {
        profile = .empty
        hasCompletedOnboarding = false
        needsRemoteSync = false
        defaults.removeObject(forKey: Key.profile)
        defaults.removeObject(forKey: Key.onboardingCompleted)
        defaults.removeObject(forKey: Key.needsRemoteSync)
    }

    private func store(_ profile: StyleProfile) {
        self.profile = profile
        do {
            defaults.set(try JSONEncoder().encode(profile), forKey: Key.profile)
        } catch {
            Log.onboarding.error("Failed to persist style profile")
        }
    }

    private func setNeedsRemoteSync(_ value: Bool) {
        needsRemoteSync = value
        defaults.set(value, forKey: Key.needsRemoteSync)
    }
}
