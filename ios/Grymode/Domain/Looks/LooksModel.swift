import Foundation
import Observation

/// Loads the outfit library, starts generation, filters, and save/unsave.
@MainActor
@Observable
final class LooksModel {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    private(set) var library: OutfitLibrary?
    private(set) var loadState: LoadState = .idle
    private(set) var isGenerating = false
    private(set) var isOpeningLook = false
    private(set) var isTogglingSave = false
    private(set) var actionError: AppError?
    var selectedOccasion: String?
    var savedOnly = false

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let maxPollAttempts: Int
    @ObservationIgnored private let pollInterval: TimeInterval

    init(
        api: APIClient?,
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        maxPollAttempts: Int = 90,
        pollInterval: TimeInterval = 2
    ) {
        self.api = api
        self.sleep = sleep
        self.maxPollAttempts = maxPollAttempts
        self.pollInterval = pollInterval
    }

    func bind(api: APIClient?) {
        self.api = api
    }

    var looks: [OutfitLook] { library?.outfits ?? [] }
    var acceptedCount: Int { library?.acceptedCount ?? 0 }
    var lockedCount: Int { library?.lockedCount ?? 0 }
    var savedCount: Int { library?.savedCount ?? 0 }
    var filterOccasions: [String] { library?.filterOccasions ?? [] }
    var hasLooks: Bool { !looks.isEmpty }
    var freeReveal: OutfitLook? { looks.first(where: \.isFreeReveal) }
    var isPremium: Bool { library?.entitlement.canOpenFullLibrary == true }
    var activeJob: OutfitJob? {
        if let job = library?.activeJob, job.isActive { return job }
        return nil
    }

    var statusMessage: String? {
        guard let job = activeJob else {
            return isGenerating ? "Composing looks from your wardrobe…" : nil
        }
        switch job.progressStage {
        case "queued": return "Queued — preparing your looks…"
        case "composing": return "Composing looks from your wardrobe…"
        case "persisting": return "Saving your library…"
        default: return "Working on your looks…"
        }
    }

    func refresh(autoGenerateIfEmpty: Bool = true) async {
        guard loadState != .loading else { return }
        loadState = library == nil ? .loading : loadState
        actionError = nil
        do throws(AppError) {
            library = try await requireAPI().send(
                LooksAPI.library(occasion: selectedOccasion, savedOnly: savedOnly)
            )
            loadState = .loaded
            if let job = library?.activeJob, job.isActive {
                await poll(jobId: job.id)
                library = try await requireAPI().send(
                    LooksAPI.library(occasion: selectedOccasion, savedOnly: savedOnly)
                )
            } else if autoGenerateIfEmpty,
                      selectedOccasion == nil,
                      !savedOnly,
                      (library?.acceptedCount ?? 0) == 0
            {
                await generateLooks()
            }
        } catch {
            Log.networking.error("Looks load failed: \(error.apiCode ?? "transport", privacy: .public)")
            if library == nil {
                loadState = .failed(error)
            } else {
                actionError = error
                loadState = .loaded
            }
        }
    }

    /// True while any unlocked look's styled image is still rendering.
    var hasStylingLooks: Bool { looks.contains(where: \.isStyling) }

    /// Quietly refreshes the library until every styled image has finished (or the view goes away).
    func followStylingLooks(interval: TimeInterval = 8, maxRefreshes: Int = 120) async {
        var refreshes = 0
        while hasStylingLooks, refreshes < maxRefreshes, !Task.isCancelled {
            do {
                try await sleep(interval)
            } catch {
                return
            }
            refreshes += 1
            guard loadState != .loading, !isGenerating, activeJob == nil else { continue }
            do throws(AppError) {
                library = try await requireAPI().send(
                    LooksAPI.library(occasion: selectedOccasion, savedOnly: savedOnly)
                )
            } catch {
                Log.networking.error("Looks visual refresh failed: \(error.apiCode ?? "transport", privacy: .public)")
            }
        }
    }

    func applyFilters(occasion: String?, savedOnly: Bool) async {
        selectedOccasion = occasion
        self.savedOnly = savedOnly
        await refresh(autoGenerateIfEmpty: false)
    }

    func generateLooks() async {
        guard !isGenerating else { return }
        isGenerating = true
        actionError = nil
        defer { isGenerating = false }
        do throws(AppError) {
            let started = try await requireAPI().send(LooksAPI.generate())
            await poll(jobId: started.job.id)
            library = try await requireAPI().send(
                LooksAPI.library(occasion: selectedOccasion, savedOnly: self.savedOnly)
            )
            loadState = .loaded
        } catch {
            actionError = error
            Log.networking.error("Looks generate failed: \(error.apiCode ?? "transport", privacy: .public)")
            await refresh(autoGenerateIfEmpty: false)
        }
    }

    /// Fetches full outfit detail when the server allows it.
    func openLook(id: UUID) async throws(AppError) -> OutfitLook {
        isOpeningLook = true
        actionError = nil
        defer { isOpeningLook = false }
        return try await requireAPI().send(LooksAPI.outfit(id: id))
    }

    func toggleSave(_ look: OutfitLook) async -> OutfitLook? {
        guard !look.isLocked else { return nil }
        guard !isTogglingSave else { return nil }
        isTogglingSave = true
        actionError = nil
        defer { isTogglingSave = false }
        do throws(AppError) {
            if look.isSaved {
                _ = try await requireAPI().send(LooksAPI.unsave(id: look.id))
                let updated = look.withSaved(false)
                patchLook(updated)
                return updated
            } else {
                let updated = try await requireAPI().send(LooksAPI.save(id: look.id))
                patchLook(updated)
                return updated
            }
        } catch {
            actionError = error
            Log.networking.error("Looks save toggle failed: \(error.apiCode ?? "transport", privacy: .public)")
            return nil
        }
    }

    func presentError(_ error: AppError) {
        actionError = error
    }

    private func patchLook(_ look: OutfitLook) {
        guard let current = library else { return }
        let wasSaved = current.outfits.first(where: { $0.id == look.id })?.isSaved ?? false
        var outfits = current.outfits
        if let index = outfits.firstIndex(where: { $0.id == look.id }) {
            outfits[index] = look
        }
        var nextSaved = current.savedCount
        if look.isSaved, !wasSaved { nextSaved += 1 }
        if !look.isSaved, wasSaved { nextSaved = max(0, nextSaved - 1) }
        if savedOnly, !look.isSaved {
            outfits.removeAll { $0.id == look.id }
        }
        library = OutfitLibrary(
            acceptedCount: current.acceptedCount,
            lockedCount: current.lockedCount,
            savedCount: nextSaved,
            entitlement: current.entitlement,
            filterOccasions: current.filterOccasions,
            outfits: outfits,
            activeJob: current.activeJob
        )
    }

    private func poll(jobId: UUID) async {
        for attempt in 0..<maxPollAttempts {
            if Task.isCancelled { return }
            do throws(AppError) {
                let job = try await requireAPI().send(LooksAPI.job(id: jobId))
                if let current = library {
                    library = OutfitLibrary(
                        acceptedCount: max(job.acceptedCount, current.acceptedCount),
                        lockedCount: current.lockedCount,
                        savedCount: current.savedCount,
                        entitlement: current.entitlement,
                        filterOccasions: current.filterOccasions,
                        outfits: current.outfits,
                        activeJob: job
                    )
                }
                if job.status == .failed {
                    actionError = Self.generationFailure(code: job.errorCode)
                    return
                }
                if job.status == .succeeded {
                    return
                }
            } catch {
                actionError = error
                return
            }
            if attempt + 1 < maxPollAttempts {
                do {
                    try await sleep(pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    static func generationFailure(code: String?) -> AppError {
        let message =
            switch code {
            case "insufficient_wardrobe":
                "Confirm at least two labelled pieces, including a top and a bottom or a dress, to build looks."
            case "no_valid_outfits":
                "Grymode couldn't build a complete look from your confirmed pieces yet. Add a top and a bottom, or a dress, then try again."
            default:
                "Grymode couldn't style new looks right now. Please try again in a moment."
            }
        return .api(
            status: 503,
            code: code ?? "generation_failed",
            message: message,
            requestID: nil,
            retryable: code != "insufficient_wardrobe" && code != "no_valid_outfits"
        )
    }

    private func requireAPI() throws(AppError) -> APIClient {
        guard let api else { throw .configuration("The Grymode API isn't configured for this build.") }
        return api
    }
}
