import Foundation

/// Every failure the presentation layer can receive. Messages are safe to show to users;
/// internal details (stack traces, provider errors, prompts) never reach this type.
enum AppError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case cancelled
    /// The session is missing or expired; the user must sign in again.
    case unauthorized(requestID: String?)
    /// A structured error returned by the Grymode API (`code`, `message`, `request_id`, `retryable`).
    case api(status: Int, code: String, message: String, requestID: String?, retryable: Bool)
    case invalidResponse
    case decoding
    case configuration(String)
    case unexpected

    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut: true
        case .api(_, _, _, _, let retryable): retryable
        case .cancelled, .unauthorized, .invalidResponse, .decoding, .configuration, .unexpected: false
        }
    }

    var requestID: String? {
        switch self {
        case .unauthorized(let requestID): requestID
        case .api(_, _, _, let requestID, _): requestID
        default: nil
        }
    }

    /// Stable machine-readable code from the API, when available.
    var apiCode: String? {
        if case .api(_, let code, _, _, _) = self { return code }
        return nil
    }

    var title: String {
        switch self {
        case .offline: "You're offline"
        case .timedOut: "This is taking too long"
        case .unauthorized: "Please sign in again"
        case .configuration: "Grymode isn't configured"
        default: "Something went wrong"
        }
    }

    var userMessage: String {
        switch self {
        case .offline:
            "Check your connection and try again. Anything you've already saved is safe."
        case .timedOut:
            "The request didn't finish in time. Please try again."
        case .cancelled:
            "The request was cancelled."
        case .unauthorized:
            "Your session has ended. Sign in to continue."
        case .api(_, _, let message, _, _):
            message
        case .invalidResponse, .decoding:
            "We received an unexpected response. Please try again shortly."
        case .configuration(let detail):
            detail
        case .unexpected:
            "An unexpected error occurred. Please try again."
        }
    }
}
