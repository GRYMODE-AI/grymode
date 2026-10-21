import XCTest

@testable import Grymode

final class RetryPolicyTests: XCTestCase {
    func testRetriesOnlyRetryableErrorsWithinAttemptBudget() {
        let policy = RetryPolicy.standard
        XCTAssertTrue(policy.shouldRetry(after: .offline, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(after: .timedOut, attempt: 2))
        XCTAssertFalse(policy.shouldRetry(after: .offline, attempt: 3))
        XCTAssertFalse(policy.shouldRetry(after: .decoding, attempt: 1))
        XCTAssertFalse(policy.shouldRetry(after: .unauthorized(requestID: nil), attempt: 1))
        XCTAssertFalse(policy.shouldRetry(after: .cancelled, attempt: 1))
        XCTAssertFalse(RetryPolicy.none.shouldRetry(after: .offline, attempt: 1))
    }

    func testBackoffGrowsExponentiallyAndIsCapped() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 0.5, maxDelay: 4)
        XCTAssertEqual(policy.delay(afterAttempt: 1, jitter: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 2, jitter: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 3, jitter: 1), 2, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 6, jitter: 1), 4, accuracy: 0.0001)
    }

    func testJitterKeepsDelayBetweenHalfAndFullBackoff() {
        let policy = RetryPolicy.standard
        XCTAssertEqual(policy.delay(afterAttempt: 2, jitter: 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 2, jitter: 5), 1, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 2, jitter: -1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RetryPolicy.none.delay(afterAttempt: 1), 0)
        XCTAssertEqual(policy.delay(afterAttempt: 0), 0)
    }
}
