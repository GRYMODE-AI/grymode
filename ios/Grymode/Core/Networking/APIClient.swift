import Foundation

/// Typed client for the Grymode REST API.
///
/// Responsibilities: attaching the access token, one silent refresh on 401, bounded retries for
/// transient failures, cancellation, and mapping every failure to `AppError`.
final class APIClient: Sendable {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private let builder: RequestBuilder
    private let transport: any HTTPTransport
    private let tokens: any AccessTokenProviding
    private let sleep: Sleeper
    private let makeRequestID: @Sendable () -> String

    init(
        builder: RequestBuilder,
        transport: any HTTPTransport,
        tokens: any AccessTokenProviding,
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        makeRequestID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.builder = builder
        self.transport = transport
        self.tokens = tokens
        self.sleep = sleep
        self.makeRequestID = makeRequestID
    }

    func send<Response>(_ endpoint: Endpoint<Response>) async throws(AppError) -> Response {
        var attempt = 0
        var hasRefreshedToken = false

        while true {
            attempt += 1
            do throws(AppError) {
                return try await perform(endpoint, forceRefresh: false)
            } catch .unauthorized(let requestID) where endpoint.requiresAuthentication && !hasRefreshedToken {
                hasRefreshedToken = true
                do throws(AppError) {
                    return try await perform(endpoint, forceRefresh: true)
                } catch {
                    if case .unauthorized = error { throw .unauthorized(requestID: requestID) }
                    throw error
                }
            } catch {
                guard endpoint.retryPolicy.shouldRetry(after: error, attempt: attempt) else { throw error }
                let delay = endpoint.retryPolicy.delay(afterAttempt: attempt, jitter: Double.random(in: 0...1))
                Log.networking.info(
                    "Retrying \(endpoint.path, privacy: .public) attempt \(attempt + 1) in \(delay, privacy: .public)s"
                )
                do {
                    try await sleep(delay)
                } catch {
                    throw .cancelled
                }
            }
        }
    }

    /// PUTs bytes to a pre-signed URL (for example Supabase Storage). Does not use `/v1` path rules
    /// or attach auth headers. Never log the destination URL — it is a capability credential.
    func putBytes(
        _ data: Data,
        to url: URL,
        contentType: String,
        timeout: TimeInterval = 120
    ) async throws(AppError) {
        if Task.isCancelled { throw .cancelled }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // Supabase Storage: allow replacing an object at the same path.
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let responseData: Data
        let response: HTTPURLResponse
        do {
            (responseData, response) = try await transport.send(request)
        } catch {
            Log.networking.error("Signed upload PUT failed")
            throw APIErrorMapper.map(error)
        }

        guard (200..<300).contains(response.statusCode) else {
            Log.networking.error("Signed upload PUT status \(response.statusCode, privacy: .public)")
            throw APIErrorMapper.map(status: response.statusCode, data: responseData, headerRequestID: nil)
        }
    }

    private func perform<Response>(
        _ endpoint: Endpoint<Response>,
        forceRefresh: Bool
    ) async throws(AppError) -> Response {
        if Task.isCancelled { throw .cancelled }

        var token: String?
        if endpoint.requiresAuthentication {
            token = forceRefresh ? await tokens.refreshAccessToken() : await tokens.currentAccessToken()
            guard token != nil else { throw .unauthorized(requestID: nil) }
        }

        let requestID = makeRequestID()
        let request = try builder.makeRequest(for: endpoint, accessToken: token, requestID: requestID)
        let started = ContinuousClock.now

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            let mapped = APIErrorMapper.map(error)
            Log.networking.error(
                "\(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public) failed request_id=\(requestID, privacy: .public)"
            )
            throw mapped
        }

        let elapsed = ContinuousClock.now - started
        Log.networking.info(
            "\(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public) \(response.statusCode, privacy: .public) request_id=\(requestID, privacy: .public) \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)"
        )

        guard (200..<300).contains(response.statusCode) else {
            let headerRequestID = response.value(forHTTPHeaderField: "X-Request-ID") ?? requestID
            throw APIErrorMapper.map(status: response.statusCode, data: data, headerRequestID: headerRequestID)
        }

        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try JSONCoding.makeDecoder().decode(Response.self, from: data)
        } catch {
            Log.networking.error("Decoding failed for \(endpoint.path, privacy: .public)")
            throw .decoding
        }
    }
}
