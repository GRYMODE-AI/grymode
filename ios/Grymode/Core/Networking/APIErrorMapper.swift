import Foundation

/// The backend error contract: `{ "code", "message", "request_id", "retryable" }`.
struct APIErrorPayload: Decodable, Equatable, Sendable {
    let code: String
    let message: String
    let requestId: String?
    let retryable: Bool
}

/// Maps transport and HTTP failures onto `AppError`.
enum APIErrorMapper {
    static func map(_ error: any Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError { return map(urlError) }
        return .unexpected
    }

    static func map(_ error: URLError) -> AppError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .offline
        case .timedOut:
            .timedOut
        case .cancelled:
            .cancelled
        default:
            .unexpected
        }
    }

    /// Maps a non-2xx response. Falls back to a generic message when the body is not the API contract
    /// (for example, an HTML page from a load balancer).
    static func map(status: Int, data: Data, headerRequestID: String?) -> AppError {
        let payload = try? JSONCoding.makeDecoder().decode(APIErrorPayload.self, from: data)
        let requestID = payload?.requestId ?? headerRequestID

        if status == 401 {
            return .unauthorized(requestID: requestID)
        }
        if let payload {
            return .api(
                status: status,
                code: payload.code,
                message: payload.message,
                requestID: requestID,
                retryable: payload.retryable
            )
        }
        let isTransient = status == 408 || status == 429 || (500...599).contains(status)
        return .api(
            status: status,
            code: "http_\(status)",
            message: isTransient
                ? "Grymode is temporarily unavailable. Please try again shortly."
                : "We couldn't complete that request.",
            requestID: requestID,
            retryable: isTransient
        )
    }
}
