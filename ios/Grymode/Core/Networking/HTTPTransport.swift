import Foundation

/// Sends a request and returns the raw response. Abstracted so the API client can be tested
/// without the network.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    static func makeDefault() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        return (data, httpResponse)
    }
}

/// Supplies the current session's access token (`AuthService` in the app).
protocol AccessTokenProviding: Sendable {
    func currentAccessToken() async -> String?
    /// Attempts to refresh an expired session. Returns `nil` when the user must sign in again.
    func refreshAccessToken() async -> String?
}

/// Used when sign-in isn't configured: protected calls fail fast as unauthorised.
struct SignedOutTokenProvider: AccessTokenProviding {
    func currentAccessToken() async -> String? { nil }
    func refreshAccessToken() async -> String? { nil }
}
