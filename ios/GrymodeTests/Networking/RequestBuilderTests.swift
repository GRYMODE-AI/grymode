import XCTest

@testable import Grymode

final class RequestBuilderTests: XCTestCase {
    private func makeBuilder() throws -> RequestBuilder {
        RequestBuilder(baseURL: try XCTUnwrap(URL(string: "https://api.example.test")), clientVersion: "0.1.0 (1)")
    }

    func testBuildsVersionedURLWithQueryAndStandardHeaders() throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .get,
            path: "/v1/outfits",
            queryItems: [URLQueryItem(name: "category", value: "work")]
        )

        let request = try makeBuilder().makeRequest(for: endpoint, accessToken: "abc", requestID: "r-1")

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v1/outfits?category=work")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "r-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Version"), "0.1.0 (1)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testBodyAndIdempotencyKeyAreAttached() throws {
        let body = Data(#"{"a":1}"#.utf8)
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/v1/generation-jobs",
            body: body,
            idempotencyKey: "key-1",
            timeout: 12
        )

        let request = try makeBuilder().makeRequest(for: endpoint, accessToken: nil, requestID: "r-2")

        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "key-1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.timeoutInterval, 12)
    }

    func testRejectsUnversionedPaths() throws {
        let builder = try makeBuilder()
        let error = capturedError {
            try builder.makeRequest(
                for: Endpoint<EmptyResponse>(method: .get, path: "/outfits"),
                accessToken: nil,
                requestID: "r"
            )
        }
        XCTAssertEqual(error, .configuration("API paths must be versioned under /v1."))
    }

    func testDefaultRetryPolicyFollowsIdempotency() {
        XCTAssertEqual(Endpoint<EmptyResponse>(method: .get, path: "/v1/a").retryPolicy, .standard)
        XCTAssertEqual(Endpoint<EmptyResponse>(method: .delete, path: "/v1/a").retryPolicy, .standard)
        XCTAssertEqual(Endpoint<EmptyResponse>(method: .post, path: "/v1/a").retryPolicy, .none)
        XCTAssertEqual(Endpoint<EmptyResponse>(method: .patch, path: "/v1/a").retryPolicy, .none)
        XCTAssertEqual(
            Endpoint<EmptyResponse>(method: .post, path: "/v1/a", idempotencyKey: "k").retryPolicy,
            .standard
        )
    }
}
