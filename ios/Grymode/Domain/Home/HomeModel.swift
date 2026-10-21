import Foundation
import Observation

/// Loads today's look and home summary for the main tab.
@MainActor
@Observable
final class HomeModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    private(set) var snapshot: HomeSnapshot?
    private(set) var loadState: LoadState = .loading
    private(set) var actionError: AppError?
    private(set) var isOpeningLook = false
    private(set) var isTogglingSave = false

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var isRefreshing = false

    init(api: APIClient?) {
        self.api = api
    }

    func bind(api: APIClient?) {
        self.api = api
    }

    var todaysLook: OutfitLook? { snapshot?.todaysLook }
    var acceptedCount: Int { snapshot?.acceptedCount ?? 0 }
    var savedCount: Int { snapshot?.savedCount ?? 0 }
    var lockedCount: Int { snapshot?.lockedCount ?? 0 }
    var wardrobeCount: Int { snapshot?.wardrobeConfirmedCount ?? 0 }
    var isPremium: Bool { snapshot?.entitlement.canOpenFullLibrary == true }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if snapshot == nil { loadState = .loading }
        actionError = nil
        do throws(AppError) {
            snapshot = try await requireAPI().send(LooksAPI.home())
            loadState = .loaded
        } catch {
            Log.networking.error("Home load failed: \(error.apiCode ?? "transport", privacy: .public)")
            if snapshot == nil {
                loadState = .failed(error)
            } else {
                actionError = error
                loadState = .loaded
            }
        }
    }

    /// Quietly refreshes until today's styled image has finished rendering.
    func followTodaysLookVisual(interval: Duration = .seconds(8), maxRefreshes: Int = 90) async {
        var refreshes = 0
        while todaysLook?.isStyling == true, refreshes < maxRefreshes, !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            refreshes += 1
            await refresh()
        }
    }

    func openLook(id: UUID) async throws(AppError) -> OutfitLook {
        isOpeningLook = true
        actionError = nil
        defer { isOpeningLook = false }
        return try await requireAPI().send(LooksAPI.outfit(id: id))
    }

    func presentError(_ error: AppError) {
        actionError = error
    }

    func toggleSave(_ look: OutfitLook) async -> OutfitLook? {
        guard !look.isLocked else { return nil }
        guard !isTogglingSave else { return nil }
        isTogglingSave = true
        actionError = nil
        defer { isTogglingSave = false }
        do throws(AppError) {
            let updated: OutfitLook
            if look.isSaved {
                _ = try await requireAPI().send(LooksAPI.unsave(id: look.id))
                updated = look.withSaved(false)
            } else {
                updated = try await requireAPI().send(LooksAPI.save(id: look.id))
            }
            if let current = snapshot {
                let savedDelta: Int
                if updated.isSaved, !look.isSaved { savedDelta = 1 }
                else if !updated.isSaved, look.isSaved { savedDelta = -1 }
                else { savedDelta = 0 }
                snapshot = HomeSnapshot(
                    todaysLook: current.todaysLook?.id == updated.id ? updated : current.todaysLook,
                    acceptedCount: current.acceptedCount,
                    savedCount: max(0, current.savedCount + savedDelta),
                    lockedCount: current.lockedCount,
                    entitlement: current.entitlement,
                    wardrobeConfirmedCount: current.wardrobeConfirmedCount
                )
            }
            return updated
        } catch {
            actionError = error
            return nil
        }
    }

    private func requireAPI() throws(AppError) -> APIClient {
        guard let api else { throw .configuration("The Grymode API isn't configured for this build.") }
        return api
    }
}
