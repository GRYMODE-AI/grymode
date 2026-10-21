import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// Methods that are safe to repeat without an idempotency key.
    var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: true
        case .post, .patch: false
        }
    }
}

/// Response type for endpoints that return no body (for example, HTTP 204).
struct EmptyResponse: Decodable, Sendable, Equatable {}

/// A typed description of one Grymode API call. All application paths begin with `/v1`.
struct Endpoint<Response: Decodable & Sendable>: Sendable {
    var method: HTTPMethod
    var path: String
    var queryItems: [URLQueryItem]
    var body: Data?
    var requiresAuthentication: Bool
    /// Required for expensive or non-idempotent operations so retries never duplicate work.
    var idempotencyKey: String?
    var timeout: TimeInterval
    var retryPolicy: RetryPolicy

    init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        idempotencyKey: String? = nil,
        timeout: TimeInterval = 30,
        retryPolicy: RetryPolicy? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.idempotencyKey = idempotencyKey
        self.timeout = timeout
        let canRepeatSafely = method.isIdempotent || idempotencyKey != nil
        self.retryPolicy = retryPolicy ?? (canRepeatSafely ? .standard : .none)
    }
}

enum JSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(value, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) throws(AppError) -> Data {
        do {
            return try makeEncoder().encode(value)
        } catch {
            throw .unexpected
        }
    }
}
