import Foundation

/// The four Supabase Auth (GoTrue) REST calls the app needs: email one-time codes, token
/// refresh, and sign-out. Authenticates to Supabase with the public publishable key only.
struct SupabaseAuthClient: Sendable {
    let baseURL: URL
    let publishableKey: String
    let transport: any HTTPTransport
    var now: @Sendable () -> Date = { Date() }

    /// Sends a 6-digit sign-in code. Creates the account on first use.
    func sendEmailCode(to email: String) async throws(AppError) {
        let body = try JSONCoding.encode(OTPRequest(email: email, createUser: true))
        _ = try await send(path: "otp", body: body, purpose: .requestCode)
    }

    func verifyEmailCode(_ code: String, email: String) async throws(AppError) -> AuthSession {
        let body = try JSONCoding.encode(VerifyRequest(type: "email", email: email, token: code))
        return try session(from: await send(path: "verify", body: body, purpose: .verifyCode))
    }

    func refresh(refreshToken: String) async throws(AppError) -> AuthSession {
        let body = try JSONCoding.encode(RefreshRequest(refreshToken: refreshToken))
        let data = try await send(
            path: "token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body,
            purpose: .refresh
        )
        return try session(from: data)
    }

    /// Revokes this device's refresh token on the server.
    func signOut(accessToken: String) async throws(AppError) {
        _ = try await send(
            path: "logout",
            query: [URLQueryItem(name: "scope", value: "local")],
            body: nil,
            accessToken: accessToken,
            purpose: .signOut
        )
    }

    // MARK: - Transport

    enum Purpose {
        case requestCode, verifyCode, refresh, signOut
    }

    private func send(
        path: String,
        query: [URLQueryItem] = [],
        body: Data?,
        accessToken: String? = nil,
        purpose: Purpose
    ) async throws(AppError) -> Data {
        var components = URLComponents(
            url: baseURL.appending(path: "auth/v1").appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw .configuration("Unable to build the sign-in request.") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw APIErrorMapper.map(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = AuthErrorMapper.map(status: response.statusCode, data: data, purpose: purpose)
            Log.auth.error("Auth \(path, privacy: .public) failed with status \(response.statusCode, privacy: .public)")
            throw error
        }
        return data
    }

    private func session(from data: Data) throws(AppError) -> AuthSession {
        let token: TokenResponse
        do {
            token = try JSONCoding.makeDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw .decoding
        }
        return AuthSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(token.expiresIn)),
            user: AuthUser(id: token.user.id, email: token.user.email)
        )
    }
}

private struct OTPRequest: Encodable {
    let email: String
    let createUser: Bool
}

private struct VerifyRequest: Encodable {
    let type: String
    let email: String
    let token: String
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct TokenResponse: Decodable {
    struct User: Decodable {
        let id: UUID
        let email: String?
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
}
