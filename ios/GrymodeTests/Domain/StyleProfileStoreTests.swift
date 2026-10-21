import XCTest

@testable import Grymode

@MainActor
final class StyleProfileStoreTests: XCTestCase {
    func testStartsEmptyAndNotOnboarded() throws {
        let store = StyleProfileStore(defaults: try makeEphemeralDefaults())
        XCTAssertEqual(store.profile, .empty)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testCompletingOnboardingPersistsAcrossInstances() throws {
        let defaults = try makeEphemeralDefaults()
        var profile = StyleProfile.empty
        profile.toggle(.first, on: .character)
        profile.toggle(Occasion.weekend)

        StyleProfileStore(defaults: defaults).completeOnboarding(with: profile)
        let reloaded = StyleProfileStore(defaults: defaults)

        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        XCTAssertEqual(reloaded.profile, profile)
    }

    func testSavingDoesNotCompleteOnboarding() throws {
        let defaults = try makeEphemeralDefaults()
        var profile = StyleProfile.empty
        profile.toggle(PalettePreference.neutrals)

        StyleProfileStore(defaults: defaults).save(profile)
        let reloaded = StyleProfileStore(defaults: defaults)

        XCTAssertEqual(reloaded.profile, profile)
        XCTAssertFalse(reloaded.hasCompletedOnboarding)
    }

    func testResetClearsEverything() throws {
        let defaults = try makeEphemeralDefaults()
        let store = StyleProfileStore(defaults: defaults)
        var profile = StyleProfile.empty
        profile.toggle(.second, on: .silhouette)
        store.completeOnboarding(with: profile)

        store.reset()

        XCTAssertEqual(store.profile, .empty)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertFalse(StyleProfileStore(defaults: defaults).hasCompletedOnboarding)
    }

    func testLocalEditsStayFlaggedUntilTheUploadedVersionIsConfirmed() throws {
        let defaults = try makeEphemeralDefaults()
        let store = StyleProfileStore(defaults: defaults)
        var first = StyleProfile.empty
        first.toggle(Occasion.travel)
        var second = first
        second.toggle(PalettePreference.colour)

        store.adoptRemote(.empty)
        XCTAssertFalse(store.needsRemoteSync)
        store.save(first)
        store.save(second)
        store.markSynced(first)
        XCTAssertTrue(store.needsRemoteSync, "A newer edit made during an upload must still be uploaded")
        XCTAssertTrue(StyleProfileStore(defaults: defaults).needsRemoteSync)

        store.markSynced(second)
        XCTAssertFalse(store.needsRemoteSync)
        XCTAssertTrue(StyleProfileStore(defaults: defaults).hasCompletedOnboarding)
    }

    func testCorruptStoredProfileFallsBackToEmpty() throws {
        let defaults = try makeEphemeralDefaults()
        defaults.set(Data("not json".utf8), forKey: StyleProfileStore.Key.profile)
        XCTAssertEqual(StyleProfileStore(defaults: defaults).profile, .empty)
    }
}
