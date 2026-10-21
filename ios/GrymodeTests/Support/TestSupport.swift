import Foundation
import XCTest

@testable import Grymode

/// Runs an operation and returns the `AppError` it threw, or `nil` if it succeeded.
/// Any other error type fails the test, because the app layers must only surface `AppError`.
func capturedError<T>(
    isolation: isolated (any Actor)? = #isolation,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> T
) async -> AppError? {
    do {
        _ = try await operation()
        return nil
    } catch {
        return appError(from: error, file: file, line: line)
    }
}

func capturedError<T>(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> T) -> AppError? {
    do {
        _ = try operation()
        return nil
    } catch {
        return appError(from: error, file: file, line: line)
    }
}

private func appError(from error: any Error, file: StaticString, line: UInt) -> AppError? {
    guard let appError = error as? AppError else {
        XCTFail("Expected AppError, got \(type(of: error))", file: file, line: line)
        return nil
    }
    return appError
}

/// A transport that replays scripted outcomes and records every request it receives.
actor StubTransport: HTTPTransport {
    enum Outcome: Sendable {
        case response(status: Int, body: Data = Data(), headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private var outcomes: [Outcome]
    private(set) var requests: [URLRequest] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !outcomes.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        switch outcomes.removeFirst() {
        case .response(let status, let body, let headers):
            guard
                let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            else {
                throw URLError(.badServerResponse)
            }
            return (body, response)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

actor StubTokenProvider: AccessTokenProviding {
    private var current: String?
    private let refreshed: String?
    private(set) var refreshCount = 0

    init(current: String?, refreshed: String? = nil) {
        self.current = current
        self.refreshed = refreshed
    }

    func currentAccessToken() async -> String? { current }

    func refreshAccessToken() async -> String? {
        refreshCount += 1
        current = refreshed
        return refreshed
    }
}

actor SleepRecorder {
    private(set) var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }
}

func makeEphemeralDefaults(file: StaticString = #filePath, line: UInt = #line) throws -> UserDefaults {
    let suiteName = "tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
