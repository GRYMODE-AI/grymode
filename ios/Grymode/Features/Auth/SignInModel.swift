import Foundation
import Observation

/// State for the email one-time-code sign-in screens.
@MainActor
@Observable
final class SignInModel {
    static let codeLength = 6
    /// Matches the server's minimum interval between code emails.
    static let resendInterval: TimeInterval = 60

    var email = ""
    var code = "" {
        didSet {
            let sanitized = String(code.filter(\.isASCIIDigit).prefix(Self.codeLength))
            if sanitized != code { code = sanitized }
        }
    }

    private(set) var isWorking = false
    private(set) var error: AppError?
    private(set) var sentTo: String?
    private(set) var resendAvailableAt: Date?
    /// True when the server declined to send another code because one went out moments ago.
    private(set) var isUsingEarlierCode = false

    @ObservationIgnored private let account: AccountModel
    @ObservationIgnored private let now: () -> Date

    init(account: AccountModel, now: @escaping () -> Date = { Date() }) {
        self.account = account
        self.now = now
    }

    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var canSendCode: Bool { Self.isPlausibleEmail(normalizedEmail) && !isWorking }
    var canVerify: Bool { code.count == Self.codeLength && !isWorking }

    func secondsUntilResend(at date: Date) -> Int {
        guard let resendAvailableAt else { return 0 }
        return max(0, Int(resendAvailableAt.timeIntervalSince(date).rounded(.up)))
    }

    /// Sends a code to the entered address. Returns true when the user should enter the code.
    func sendCode() async -> Bool {
        let address = normalizedEmail
        guard Self.isPlausibleEmail(address) else {
            error = .api(
                status: 422, code: "invalid_email", message: "Enter a valid email address.", requestID: nil,
                retryable: false)
            return false
        }
        // Re-entering the same address within the resend window reuses the code already sent.
        if sentTo == address, secondsUntilResend(at: now()) > 0 {
            error = nil
            return true
        }
        if await perform({ () async throws(AppError) in try await self.account.sendCode(to: address) }) {
            codeSent(to: address, earlier: false)
            return true
        }
        if error?.isCodeRecentlySent == true {
            error = nil
            codeSent(to: address, earlier: true)
            return true
        }
        return false
    }

    func resendCode() async {
        guard let address = sentTo, secondsUntilResend(at: now()) == 0 else { return }
        if await perform({ () async throws(AppError) in try await self.account.sendCode(to: address) }) {
            codeSent(to: address, earlier: false)
        } else if error?.isCodeRecentlySent == true {
            error = nil
            resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
        }
    }

    private func codeSent(to address: String, earlier: Bool) {
        sentTo = address
        code = ""
        isUsingEarlierCode = earlier
        // When the server reports an earlier code, the remaining wait is at most a full interval.
        resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
    }

    /// Verifies the entered code. Returns true once the user is signed in.
    func verify() async -> Bool {
        guard let address = sentTo, code.count == Self.codeLength else { return false }
        let entered = code
        let ok = await perform { () async throws(AppError) in
            try await self.account.verify(code: entered, email: address)
        }
        // A code from a previous send may already have been used (sign-out → immediate sign-in).
        if !ok, error?.apiCode == "invalid_code" { isUsingEarlierCode = false }
        return ok
    }

    func clearError() {
        error = nil
    }

    private func perform(_ work: () async throws(AppError) -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do throws(AppError) {
            try await work()
            return true
        } catch {
            self.error = error
            return false
        }
    }

    /// A deliberately loose check; the server is the authority on what it accepts.
    static func isPlausibleEmail(_ value: String) -> Bool {
        guard value.count <= 254, !value.contains(where: \.isWhitespace) else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

extension AppError {
    fileprivate var isCodeRecentlySent: Bool {
        if case .api(_, let code, _, _, _) = self { return code == AuthErrorMapper.codeRecentlySent }
        return false
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
