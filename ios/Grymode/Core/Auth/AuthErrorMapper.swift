import Foundation

/// Maps Supabase Auth error responses onto user-safe `AppError`s.
///
/// Supabase returns `{ "code", "error_code", "msg" }` (or the older `{ "error", "error_description" }`).
/// Its messages are never shown directly; each known case gets Grymode's own wording.
enum AuthErrorMapper {
    /// Returned when Supabase refuses a new code because one was sent to the same address
    /// within the last minute. That earlier code may still work, or it may already have been used
    /// (for example after sign-out and an immediate sign-in). The client should offer both paths.
    static let codeRecentlySent = "code_recently_sent"

    private struct Payload: Decodable {
        let errorCode: String?
        let error: String?
        let msg: String?
    }

    /// Seconds Supabase asks the client to wait before another code email, when present.
    static func retryAfterSeconds(in data: Data) -> TimeInterval? {
        let payload = try? JSONCoding.makeDecoder().decode(Payload.self, from: data)
        guard let msg = payload?.msg,
            let match = msg.range(of: #"after (\d+) seconds?"#, options: .regularExpression)
        else { return nil }
        let digits = msg[match].filter(\.isNumber)
        guard let value = TimeInterval(digits), value > 0 else { return nil }
        return value
    }

    static func map(status: Int, data: Data, purpose: SupabaseAuthClient.Purpose) -> AppError {
        let payload = try? JSONCoding.makeDecoder().decode(Payload.self, from: data)
        let code = payload?.errorCode ?? payload?.error

        if purpose == .refresh, (400...404).contains(status) {
            return .unauthorized(requestID: nil)
        }
        // The per-address throttle ("…you can only request this after 42 seconds.") shares its
        // error code with the project-wide email cap; only the former means a recent email exists.
        if purpose == .requestCode, code == "over_email_send_rate_limit",
            retryAfterSeconds(in: data) != nil
        {
            return .api(
                status: status,
                code: codeRecentlySent,
                message: "We sent a code to this address less than a minute ago.",
                requestID: nil,
                retryable: true
            )
        }

        switch code {
        case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit":
            return rateLimited(status: status)
        case "otp_expired", "otp_disabled", "invalid_credentials":
            return .api(
                status: status,
                code: "invalid_code",
                message: "That code is incorrect or has expired. Check your latest email or request a new code.",
                requestID: nil,
                retryable: false
            )
        case "email_address_invalid", "validation_failed", "email_address_not_authorized":
            return .api(
                status: status,
                code: "invalid_email",
                message: "Enter a valid email address.",
                requestID: nil,
                retryable: false
            )
        case "signup_disabled", "email_provider_disabled":
            return .api(
                status: status,
                code: "sign_in_unavailable",
                message: "Email sign-in isn't available right now.",
                requestID: nil,
                retryable: false
            )
        default:
            break
        }

        if status == 429 { return rateLimited(status: status) }
        if (500...599).contains(status) {
            return .api(
                status: status,
                code: "auth_unavailable",
                message: "Sign-in is temporarily unavailable. Please try again shortly.",
                requestID: nil,
                retryable: true
            )
        }
        if purpose == .verifyCode, (400...403).contains(status) {
            return .api(
                status: status,
                code: "invalid_code",
                message: "That code is incorrect or has expired. Check your latest email or request a new code.",
                requestID: nil,
                retryable: false
            )
        }
        return .api(
            status: status,
            code: code ?? "auth_error",
            message: "We couldn't sign you in. Please try again.",
            requestID: nil,
            retryable: false
        )
    }

    private static func rateLimited(status: Int) -> AppError {
        .api(
            status: status,
            code: "rate_limited",
            message: "Too many attempts. Please wait a minute and try again.",
            requestID: nil,
            retryable: true
        )
    }
}
