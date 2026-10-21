import Foundation

/// Bounded exponential backoff for transient failures. Permanent errors are never retried.
struct RetryPolicy: Equatable, Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)
    static let standard = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 4)

    func shouldRetry(after error: AppError, attempt: Int) -> Bool {
        attempt < maxAttempts && error.isRetryable
    }

    /// Delay before the next attempt. `jitter` in 0...1 spreads retries from many clients.
    func delay(afterAttempt attempt: Int, jitter: Double = 0.5) -> TimeInterval {
        guard attempt >= 1, baseDelay > 0 else { return 0 }
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        let capped = min(exponential, maxDelay)
        let clampedJitter = min(max(jitter, 0), 1)
        return capped * (0.5 + clampedJitter * 0.5)
    }
}
