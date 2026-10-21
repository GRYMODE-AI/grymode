import XCTest

@testable import Grymode

final class APIClientTests: XCTestCase {
    private struct Item: Decodable, Equatable, Sendable {
        let itemId: String
        let displayName: String
    }

    private let baseURL = URL(string: "https://api.example.test")

    private func makeClient(
        transport: StubTransport,
        tokens: StubTokenProvider = StubTokenProvider(current: "token-1"),
        sleeper: SleepRecorder = SleepRecorder()
    ) throws -> APIClient {
        APIClient(
            builder: RequestBuilder(baseURL: try XCTUnwrap(baseURL), clientVersion: "0.1.0 (1)"),
            transport: transport,
            tokens: tokens,
            sleep: { await sleeper.record($0) },
            makeRequestID: { "req-local" }
        )
    }

    private func json(_ string: String) -> Data { Data(string.utf8) }

    func testSuccessDecodesSnakeCaseAndAttachesBearerToken() async throws {
        let transport = StubTransport([
            .response(status: 200, body: json(#"{"item_id":"a1","display_name":"Navy blazer"}"#))
        ])
        let client = try makeClient(transport: transport)

        let item = try await client.send(Endpoint<Item>(method: .get, path: "/v1/items/a1"))

        XCTAssertEqual(item, Item(itemId: "a1", displayName: "Navy blazer"))
        let request = try await unwrapAsync(await transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "req-local")
    }

    func testAuthenticatedCallWithoutSessionFailsBeforeTouchingNetwork() async throws {
        let transport = StubTransport([.response(status: 200)])
        let client = try makeClient(transport: transport, tokens: StubTokenProvider(current: nil))

        let error = await capturedError { try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/me")) }

        XCTAssertEqual(error, .unauthorized(requestID: nil))
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testPublicEndpointDoesNotSendAuthorization() async throws {
        let transport = StubTransport([.response(status: 204)])
        let client = try makeClient(transport: transport, tokens: StubTokenProvider(current: nil))

        let response = try await client.send(
            Endpoint<EmptyResponse>(method: .get, path: "/v1/health", requiresAuthentication: false)
        )

        XCTAssertEqual(response, EmptyResponse())
        let request = try await unwrapAsync(await transport.requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testRetriesTransientServerErrorsForIdempotentRequests() async throws {
        let transport = StubTransport([
            .response(status: 503),
            .failure(.networkConnectionLost),
            .response(status: 200, body: json(#"{"item_id":"a1","display_name":"Tee"}"#)),
        ])
        let sleeper = SleepRecorder()
        let client = try makeClient(transport: transport, sleeper: sleeper)

        let item = try await client.send(Endpoint<Item>(method: .get, path: "/v1/items/a1"))

        XCTAssertEqual(item.itemId, "a1")
        let requestCount = await transport.requests.count
        let delays = await sleeper.delays
        XCTAssertEqual(requestCount, 3)
        XCTAssertEqual(delays.count, 2)
    }

    func testStopsRetryingAfterMaxAttempts() async throws {
        let transport = StubTransport([.response(status: 503), .response(status: 503), .response(status: 503)])
        let client = try makeClient(transport: transport)

        let error = await capturedError { try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/x")) }

        XCTAssertEqual(error?.isRetryable, true)
        XCTAssertEqual(error?.apiCode, "http_503")
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, RetryPolicy.standard.maxAttempts)
    }

    func testDoesNotRetryClientErrorsAndSurfacesContract() async throws {
        let body = json(
            #"{"code":"invalid_item","message":"That item can't be saved.","request_id":"srv-9","retryable":false}"#
        )
        let transport = StubTransport([.response(status: 400, body: body), .response(status: 200)])
        let client = try makeClient(transport: transport)

        let error = await capturedError { try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/x")) }

        XCTAssertEqual(
            error,
            .api(
                status: 400, code: "invalid_item", message: "That item can't be saved.", requestID: "srv-9",
                retryable: false)
        )
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testPostWithoutIdempotencyKeyIsNeverRetried() async throws {
        let transport = StubTransport([.response(status: 503), .response(status: 200)])
        let client = try makeClient(transport: transport)

        let error = await capturedError {
            try await client.send(Endpoint<EmptyResponse>(method: .post, path: "/v1/jobs"))
        }

        XCTAssertEqual(error?.apiCode, "http_503")
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testPostWithIdempotencyKeyRetriesWithTheSameKey() async throws {
        let transport = StubTransport([.response(status: 502), .response(status: 204)])
        let client = try makeClient(transport: transport)

        _ = try await client.send(
            Endpoint<EmptyResponse>(method: .post, path: "/v1/jobs", idempotencyKey: "job-123")
        )

        let keys = await transport.requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys, ["job-123", "job-123"])
    }

    func testRefreshesTokenOnceAfterUnauthorized() async throws {
        let transport = StubTransport([.response(status: 401), .response(status: 204)])
        let tokens = StubTokenProvider(current: "expired", refreshed: "fresh")
        let client = try makeClient(transport: transport, tokens: tokens)

        _ = try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/me"))

        let authorizations = await transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        let refreshCount = await tokens.refreshCount
        XCTAssertEqual(authorizations, ["Bearer expired", "Bearer fresh"])
        XCTAssertEqual(refreshCount, 1)
    }

    func testUnauthorizedAfterRefreshEndsTheSession() async throws {
        let transport = StubTransport([
            .response(status: 401, headers: ["X-Request-ID": "srv-1"]),
            .response(status: 401),
            .response(status: 204),
        ])
        let tokens = StubTokenProvider(current: "expired", refreshed: "still-bad")
        let client = try makeClient(transport: transport, tokens: tokens)

        let error = await capturedError { try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/me")) }

        XCTAssertEqual(error, .unauthorized(requestID: "srv-1"))
        let requestCount = await transport.requests.count
        let refreshCount = await tokens.refreshCount
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(refreshCount, 1)
    }

    func testFailedRefreshEndsTheSessionWithoutResending() async throws {
        let transport = StubTransport([.response(status: 401), .response(status: 204)])
        let tokens = StubTokenProvider(current: "expired", refreshed: nil)
        let client = try makeClient(transport: transport, tokens: tokens)

        let error = await capturedError { try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/me")) }

        XCTAssertEqual(error, .unauthorized(requestID: "req-local"))
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testMalformedSuccessBodyIsADecodingError() async throws {
        let transport = StubTransport([.response(status: 200, body: json(#"{"unexpected":true}"#))])
        let client = try makeClient(transport: transport)

        let error = await capturedError { try await client.send(Endpoint<Item>(method: .get, path: "/v1/items/a1")) }

        XCTAssertEqual(error, .decoding)
    }

    func testOfflineIsRetriedThenSurfaced() async throws {
        let transport = StubTransport([
            .failure(.notConnectedToInternet), .failure(.notConnectedToInternet), .failure(.notConnectedToInternet),
        ])
        let client = try makeClient(transport: transport)

        let error = await capturedError { try await client.send(Endpoint<EmptyResponse>(method: .get, path: "/v1/x")) }

        XCTAssertEqual(error, .offline)
    }
}

/// `XCTUnwrap` for values produced by an `await` expression.
func unwrapAsync<T>(
    _ expression: @autoclosure () async throws -> T?,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}
