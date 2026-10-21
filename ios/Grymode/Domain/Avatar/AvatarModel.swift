import Foundation
import Observation

/// Loads and updates the personal avatar used for try-on previews.
@MainActor
@Observable
final class AvatarModel {
    private(set) var profile: AvatarProfile?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var actionError: AppError?

    var draftHeightCm: Int = 175
    var draftBuild: BodyBuild = .regular

    @ObservationIgnored private var api: APIClient?

    init(api: APIClient?) {
        self.api = api
    }

    func bind(api: APIClient?) {
        self.api = api
    }

    var isReadyForTryOn: Bool {
        profile?.hasFace == true
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        actionError = nil
        defer { isLoading = false }
        do throws(AppError) {
            let loaded = try await requireAPI().send(AvatarAPI.get())
            profile = loaded
            draftHeightCm = loaded.heightCm
            draftBuild = loaded.bodyBuild
        } catch {
            if case .api(let status, _, _, _, _) = error, status == 404 {
                profile = nil
            } else {
                actionError = error
            }
        }
    }

    func saveMeasurements() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do throws(AppError) {
            profile = try await requireAPI().send(
                AvatarAPI.upsert(heightCm: draftHeightCm, bodyBuild: draftBuild)
            )
            return true
        } catch {
            actionError = error
            return false
        }
    }

    func uploadFaceJPEG(_ data: Data) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do throws(AppError) {
            if profile == nil {
                profile = try await requireAPI().send(
                    AvatarAPI.upsert(heightCm: draftHeightCm, bodyBuild: draftBuild)
                )
            }
            let slot = try await requireAPI().send(AvatarAPI.faceUploadSlot())
            guard let uploadURL = URL(string: slot.uploadUrl) else { throw AppError.invalidResponse }
            try await requireAPI().putBytes(data, to: uploadURL, contentType: "image/jpeg")
            profile = try await requireAPI().send(AvatarAPI.faceComplete())
            // Face and try-on reuse fixed Storage keys; drop stale decoded pixels immediately.
            GMRemoteImageCache.removeAll()
            return true
        } catch {
            actionError = error
            return false
        }
    }

    func presentError(_ error: AppError) {
        actionError = error
    }

    private func requireAPI() throws(AppError) -> APIClient {
        guard let api else { throw .configuration("The Grymode API isn't configured for this build.") }
        return api
    }
}
