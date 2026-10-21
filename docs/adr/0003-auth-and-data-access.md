# 0003 Authentication and data access

- Status: accepted
- Date: 2026-10-10

## Context

Grymode needs real accounts before wardrobe media, generation jobs, or subscriptions can belong to anyone.
The spec calls for Supabase Auth with Sign in with Apple, email sign-in where supported, session recovery,
row level security on every table, and an API that never trusts the client for authorisation.

The Apple Developer Program membership was not yet available when Phase 2 began, so Sign in with Apple could
not be configured or tested. Everything else in the account lifecycle could be.

## Decision

### Sign-in methods

1. **Email one-time code now.** Supabase Auth emails a 6-digit code (template in
   `supabase/templates/sign-in-code.html`, 10-minute expiry, one email per address per minute). Codes rather
   than magic links avoid universal-link setup and keep the user in the app.
2. **Sign in with Apple next**, added as soon as the Team ID and bundle ID exist. It is required by App Review
   if any third-party social sign-in is offered, and it is the spec's primary method. It plugs into the same
   `AuthService` as a second way to obtain a session (`signInWithIdToken`), and account deletion will revoke
   Apple tokens through the backend.

### iOS: a small Supabase Auth client instead of the Supabase Swift package

The app needs four endpoints: send code, verify code, refresh, and sign out (Sign in with Apple will add
one more). `SupabaseAuthClient` implements them in about 150 lines on the existing `HTTPTransport`, with errors
mapped onto `AppError` in Grymode's own wording.

- Avoids a second networking and session stack beside `APIClient`. The project rule is not to introduce a framework
  that duplicates an existing responsibility.
- The package's realtime, storage, and database clients would be unused: the app talks to Supabase only for
  authentication and to the Grymode API for everything else.
- Sessions live in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), excluded from backups
  and device transfer.
- `AuthService` is an actor. Concurrent requests that find an expiring token share one refresh. A refresh the
  server rejects ends the session and returns the app to the welcome screen; a refresh that fails for
  network reasons keeps the session so offline use is not mistaken for sign-out.

Revisit if the app needs Supabase features beyond auth on device, or if maintaining the client costs more
than adopting the package.

### Backend: verify tokens locally, query as the user

- The API verifies Supabase access tokens against the project's JWKS. Only asymmetric algorithms (ES256,
  RS256) are accepted, so the publishable key cannot be used to forge tokens. The verifier also checks the
  issuer, the audience (`authenticated`), the role, and the expiry. Keys are cached and refetched on rotation;
  refetches are throttled.
- The API connects to Postgres as `grymode_api`, a role that cannot log in on hosted environments without a
  Secret Manager password. It is `noinherit`, so on its own it can reach only `privacy_requests`.
- For user requests the API opens a transaction, switches to the `authenticated` role, and sets
  `request.jwt.claims` to the verified claims. Row level security then applies exactly as for Supabase's own
  APIs: `auth.uid()` is the token's subject. A bug in a query can't reach another user's rows.
- The Supabase secret key is used only for the Auth admin API (deleting a user). It is never sent to the app.

### Account deletion

`DELETE /v1/me`:

1. records a `privacy_requests` row (`processing`), with one open request per user enforced by a unique
   index;
2. deletes the auth user through the admin API, which revokes every refresh token and cascades to all
   user-owned rows;
3. marks the request `completed`.

A failure part-way leaves a `processing` row and the call can be retried safely. Later phases add wardrobe
media deletion from private storage and Apple token revocation before step 2. The app explains that deleting
the account does not cancel an App Store subscription and links to subscription management.

## Consequences

- Phase 2 ships without Sign in with Apple. It must be added before App Store submission. Because email is the
  only sign-in method, App Review does not require it now, but the spec does.
- Hosted Supabase needs custom SMTP for production email volume (the built-in sender is rate-limited for
  testing only).
- In-process rate limits apply per Cloud Run instance. Expensive operations get durable per-user quotas in the
  database when they are built.
