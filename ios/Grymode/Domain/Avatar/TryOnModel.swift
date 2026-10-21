import Foundation
import Observation

/// Starts a personal try-on for one look and polls until every angle has rendered.
@MainActor
@Observable
final class TryOnModel {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    enum Phase: Equatable {
        case starting
        case loaded
        /// The server needs height, build, or a face photo first.
        case needsAvatar(String)
        case failed(AppError)
    }

    let lookId: UUID
    private(set) var session: TryOnSession?
    private(set) var phase: Phase = .starting
    private(set) var isRetrying = false

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let pollInterval: TimeInterval
    @ObservationIgnored private let maxPolls: Int

    init(
        lookId: UUID,
        api: APIClient?,
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        pollInterval: TimeInterval = 4,
        maxPolls: Int = 150
    ) {
        self.lookId = lookId
        self.api = api
        self.sleep = sleep
        self.pollInterval = pollInterval
        self.maxPolls = maxPolls
    }

    func bind(api: APIClient?) {
        self.api = api
    }

    var isRendering: Bool { session?.status == .rendering }

    var progressMessage: String? {
        guard let session, session.previewMode == .aiMultiView else { return nil }
        switch session.status {
        case .rendering:
            if session.render(for: .front)?.status != .succeeded {
                return "Dressing you in this look… the front view comes first (about a minute)."
            }
            return "Rendering the other angles — \(session.readyCount) of \(TryOnAngle.allCases.count) ready."
        case .partial:
            return "Some angles couldn't render. You can try them again."
        case .failed:
            return "Grymode couldn't render this try-on. Please try again."
        case .ready, .idle, .unavailable:
            return nil
        }
    }

    /// Starts (or resumes) rendering, then polls while any angle is in flight.
    func start() async {
        await send(AvatarAPI.startTryOn(lookId: lookId))
        await pollWhileRendering()
    }

    /// Re-requests failed or missing angles.
    func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        await start()
    }

    private func pollWhileRendering() async {
        var polls = 0
        while isRendering, polls < maxPolls, !Task.isCancelled {
            do {
                try await sleep(pollInterval)
            } catch {
                return
            }
            polls += 1
            await send(AvatarAPI.tryOn(lookId: lookId), keepSessionOnError: true)
        }
    }

    private func send(_ endpoint: Endpoint<TryOnSession>, keepSessionOnError: Bool = false) async {
        do throws(AppError) {
            guard let api else { throw .configuration("The Grymode API isn't configured for this build.") }
            session = try await api.send(endpoint)
            phase = .loaded
        } catch {
            if case .api(let status, _, let message, _, _) = error, status == 422 {
                phase = .needsAvatar(message)
            } else if keepSessionOnError, session != nil {
                Log.networking.error("Try-on poll failed: \(error.apiCode ?? "transport", privacy: .public)")
            } else {
                phase = .failed(error)
            }
        }
    }
}
