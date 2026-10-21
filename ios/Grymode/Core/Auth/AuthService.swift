import Foundation

/// Owns the signed-in session: sign-in with an emailed code, persistence, token refresh, and
/// sign-out. Supplies access tokens to `APIClient`.
///
/// Concurrent callers that find an expiring token share a single refresh. A refresh the server
/// rejects ends the session; a refresh that fails for transient reasons keeps it.
actor AuthService: AccessTokenProviding {
    private let client: SupabaseAuthClient
    private let store: any SessionStore
    private let now: @Sendable () -> Date

    private var session: AuthSession?
    private var refreshTask: Task<AuthSession?, Never>?
    private var observers: [UUID: AsyncStream<AuthUser?>.Continuation] = [:]

    init(client: SupabaseAuthClient, store: any SessionStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.store = store
        self.now = now
    }

    var currentUser: AuthUser? { session?.user }

    /// Loads the session saved by a previous launch. Expired access tokens are refreshed lazily.
    func restoreSession() -> AuthUser? {
        session = store.load()
        return session?.user
    }

    /// Emits the signed-in user whenever it changes, including when a refresh ends the session.
    func userChanges() -> AsyncStream<AuthUser?> {
        let (stream, continuation) = AsyncStream<AuthUser?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    func sendCode(to email: String) async throws(AppError) {
        try await client.sendEmailCode(to: email)
    }

    func verify(code: String, email: String) async throws(AppError) -> AuthUser {
        let fresh = try await client.verifyEmailCode(code, email: email)
        replaceSession(with: fresh)
        Log.auth.info("Signed in with email code")
        return fresh.user
    }

    /// Ends the session on this device and asks the server to revoke its refresh token.
    func signOut() async {
        let accessToken = session?.accessToken
        endSession()
        guard let accessToken else { return }
        do {
            try await client.signOut(accessToken: accessToken)
        } catch {
            Log.auth.info("Server sign-out did not complete; the local session was still removed")
        }
    }

    /// Forgets the session without contacting the server, for example after the account has been
    /// deleted (which already revoked every token).
    func endSession() {
        refreshTask?.cancel()
        refreshTask = nil
        let hadSession = session != nil
        session = nil
        store.clear()
        if hadSession { broadcast(nil) }
    }

    // MARK: - AccessTokenProviding

    func currentAccessToken() async -> String? {
        guard let current = session else { return nil }
        guard current.needsRefresh(now: now()) else { return current.accessToken }
        // If the refresh fails transiently, send the existing token: an offline request then
        // fails as offline instead of looking like a sign-out.
        return await refreshed(from: current)?.accessToken ?? session?.accessToken
    }

    func refreshAccessToken() async -> String? {
        guard let current = session else { return nil }
        return await refreshed(from: current)?.accessToken
    }

    // MARK: - Private

    private func refreshed(from stale: AuthSession) async -> AuthSession? {
        if let inFlight = refreshTask {
            return await inFlight.value
        }
        let client = self.client
        let task = Task<AuthSession?, Never> { [weak self] in
            let result: Result<AuthSession, AppError>
            do throws(AppError) {
                result = .success(try await client.refresh(refreshToken: stale.refreshToken))
            } catch {
                result = .failure(error)
            }
            return await self?.finishRefresh(result, replacing: stale)
        }
        refreshTask = task
        let value = await task.value
        if refreshTask == task { refreshTask = nil }
        return value
    }

    private func finishRefresh(_ result: Result<AuthSession, AppError>, replacing stale: AuthSession) -> AuthSession? {
        // The user signed out or signed in again while the refresh was in flight.
        guard let current = session, current.refreshToken == stale.refreshToken else { return session }

        switch result {
        case .success(let fresh):
            replaceSession(with: fresh, notify: fresh.user != current.user)
            return fresh
        case .failure(.unauthorized):
            Log.auth.info("Session refresh was rejected; signing out")
            endSession()
            return nil
        case .failure:
            return nil
        }
    }

    private func replaceSession(with fresh: AuthSession, notify: Bool = true) {
        session = fresh
        do {
            try store.save(fresh)
        } catch {
            // The session still works for this launch; the user will be asked to sign in next time.
            Log.auth.error("Session could not be saved to the Keychain")
        }
        if notify { broadcast(fresh.user) }
    }

    private func broadcast(_ user: AuthUser?) {
        for continuation in observers.values {
            continuation.yield(user)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
