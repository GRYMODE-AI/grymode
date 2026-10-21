import Foundation

/// Builds `URLRequest`s from endpoints. Pure and deterministic so it can be unit tested.
struct RequestBuilder: Sendable {
    let baseURL: URL
    let clientVersion: String

    func makeRequest<Response>(
        for endpoint: Endpoint<Response>,
        accessToken: String?,
        requestID: String
    ) throws(AppError) -> URLRequest {
        guard endpoint.path.hasPrefix("/v1/") else {
            throw .configuration("API paths must be versioned under /v1.")
        }

        let pathURL = baseURL.appending(path: endpoint.path)
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            throw .configuration("Unable to build the request URL.")
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else {
            throw .configuration("Unable to build the request URL.")
        }

        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue(clientVersion, forHTTPHeaderField: "X-Client-Version")

        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey = endpoint.idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }
}
