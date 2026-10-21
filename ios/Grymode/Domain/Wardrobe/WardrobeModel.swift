import Foundation
import Observation

/// Loads the wardrobe, uploads photos, polls extraction jobs, and confirms labelled pieces.
@MainActor
@Observable
final class WardrobeModel {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    enum UploadPhase: Equatable {
        case idle
        case preparing
        case uploading(current: Int, total: Int)
        case processing
        case failed(AppError)
    }

    private(set) var summary: WardrobeSummary?
    private(set) var loadState: LoadState = .idle
    private(set) var uploadPhase: UploadPhase = .idle
    private(set) var isConfirming = false
    private(set) var actionError: AppError?

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let maxPollAttempts: Int
    @ObservationIgnored private let pollInterval: TimeInterval

    init(
        api: APIClient?,
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        maxPollAttempts: Int = 80,
        pollInterval: TimeInterval = 1.5
    ) {
        self.api = api
        self.sleep = sleep
        self.maxPollAttempts = maxPollAttempts
        self.pollInterval = pollInterval
    }

    func bind(api: APIClient?) {
        self.api = api
    }

    var garments: [WardrobeGarment] { summary?.garments ?? [] }
    var hasPieces: Bool { !garments.isEmpty }
    var confirmableGarments: [WardrobeGarment] { garments.filter(\.isReadyToConfirm) }
    var unlabeledCount: Int { garments.filter(\.needsLabel).count }
    var isUploading: Bool {
        switch uploadPhase {
        case .idle, .failed: false
        case .preparing, .uploading, .processing: true
        }
    }

    var uploadStatusMessage: String? {
        switch uploadPhase {
        case .idle: nil
        case .preparing: "Preparing your photos…"
        case .uploading(let current, let total): "Uploading \(current) of \(total)…"
        case .processing: "Identifying your pieces — they'll appear for review shortly…"
        case .failed: nil
        }
    }

    func refresh() async {
        guard loadState != .loading else { return }
        loadState = summary == nil ? .loading : loadState
        actionError = nil
        do throws(AppError) {
            summary = try await requireAPI().send(WardrobeAPI.summary())
            loadState = .loaded
        } catch {
            Log.wardrobe.error("Wardrobe load failed: \(error.apiCode ?? "transport", privacy: .public)")
            if summary == nil {
                loadState = .failed(error)
            } else {
                actionError = error
                loadState = .loaded
            }
        }
    }

    /// Encodes, uploads, completes, and polls until jobs settle or garments appear.
    func uploadPhotoData(_ sources: [Data]) async {
        guard !sources.isEmpty, !isUploading else { return }
        actionError = nil
        uploadPhase = .preparing
        let api: APIClient
        do throws(AppError) {
            api = try requireAPI()
        } catch {
            uploadPhase = .failed(error)
            return
        }

        var payloads: [Data] = []
        do throws(AppError) {
            for source in sources {
                payloads.append(try WardrobeImageEncoder.jpegData(from: source))
            }
        } catch {
            uploadPhase = .failed(error)
            return
        }

        var jobIds: Set<UUID> = []
        let garmentCountBefore = garments.count
        do throws(AppError) {
            for (index, bytes) in payloads.enumerated() {
                uploadPhase = .uploading(current: index + 1, total: payloads.count)
                let clientUploadId = UUID()
                let slot = try await api.send(
                    WardrobeAPI.createUpload(
                        mediaType: .photo,
                        contentType: WardrobeImageEncoder.contentType,
                        byteSize: bytes.count,
                        clientUploadId: clientUploadId
                    )
                )
                guard let uploadURL = URL(string: slot.uploadUrl) else { throw AppError.invalidResponse }
                try await api.putBytes(bytes, to: uploadURL, contentType: WardrobeImageEncoder.contentType)
                let complete = try await api.send(WardrobeAPI.completeUpload(mediaId: slot.mediaId))
                jobIds.insert(complete.jobId)
            }
            uploadPhase = .processing
            try await pollUntilSettled(
                jobIds: jobIds,
                garmentCountBefore: garmentCountBefore,
                expectedNewGarments: payloads.count
            )
            uploadPhase = .idle
            Log.wardrobe.info("Uploaded \(payloads.count, privacy: .public) wardrobe photo(s)")
        } catch {
            Log.wardrobe.error("Wardrobe upload failed: \(error.apiCode ?? "transport", privacy: .public)")
            uploadPhase = .failed(error)
            await refresh()
        }
    }

    func updateCategory(garmentId: UUID, category: GarmentCategory) async throws(AppError) {
        actionError = nil
        let updated = try await requireAPI().send(WardrobeAPI.updateGarment(id: garmentId, category: category))
        replace(updated)
    }

    func deleteGarment(id: UUID) async throws(AppError) {
        actionError = nil
        _ = try await requireAPI().send(WardrobeAPI.deleteGarment(id: id))
        guard var summary else {
            await refresh()
            return
        }
        summary.garments.removeAll { $0.id == id }
        summary.unconfirmedCount = summary.garments.filter { !$0.userConfirmed }.count
        summary.confirmedCount = summary.garments.filter(\.userConfirmed).count
        self.summary = summary
    }

    func confirmLabeledPieces() async {
        let ids = confirmableGarments.map(\.id)
        guard !ids.isEmpty else {
            actionError = .api(
                status: 422,
                code: "nothing_to_confirm",
                message: "Choose a category for each piece before confirming it.",
                requestID: nil,
                retryable: false
            )
            return
        }
        isConfirming = true
        actionError = nil
        defer { isConfirming = false }
        do throws(AppError) {
            _ = try await requireAPI().send(WardrobeAPI.confirm(garmentIds: ids))
            await refresh()
        } catch {
            actionError = error
            Log.wardrobe.error("Confirm failed: \(error.apiCode ?? "transport", privacy: .public)")
        }
    }

    func clearActionError() {
        actionError = nil
    }

    // MARK: - Private

    private func pollUntilSettled(
        jobIds: Set<UUID>,
        garmentCountBefore: Int,
        expectedNewGarments: Int
    ) async throws(AppError) {
        guard !jobIds.isEmpty else {
            await refresh()
            return
        }
        for attempt in 0..<maxPollAttempts {
            if Task.isCancelled { throw .cancelled }
            let snapshot = try await requireAPI().send(WardrobeAPI.summary())
            summary = snapshot
            loadState = .loaded

            let tracked = snapshot.jobs.filter { jobIds.contains($0.id) }
            let allTerminal =
                !tracked.isEmpty
                && tracked.allSatisfy { job in
                    job.status == .succeeded || job.status == .failed
                }
            let gained = snapshot.garments.count >= garmentCountBefore + expectedNewGarments
            if allTerminal || gained { return }

            if attempt + 1 < maxPollAttempts {
                do {
                    try await sleep(pollInterval)
                } catch {
                    throw .cancelled
                }
            }
        }
        // Timed out waiting — keep whatever we have; the user can pull to refresh.
        Log.wardrobe.info("Wardrobe processing still running after poll window")
    }

    private func replace(_ garment: WardrobeGarment) {
        guard var summary else {
            self.summary = WardrobeSummary(
                media: [], garments: [garment], jobs: [], unconfirmedCount: garment.userConfirmed ? 0 : 1,
                confirmedCount: garment.userConfirmed ? 1 : 0)
            return
        }
        if let index = summary.garments.firstIndex(where: { $0.id == garment.id }) {
            summary.garments[index] = garment
        } else {
            summary.garments.insert(garment, at: 0)
        }
        summary.unconfirmedCount = summary.garments.filter { !$0.userConfirmed }.count
        summary.confirmedCount = summary.garments.filter(\.userConfirmed).count
        self.summary = summary
    }

    private func requireAPI() throws(AppError) -> APIClient {
        guard let api else { throw .configuration("The Grymode API isn't configured for this build.") }
        return api
    }
}
