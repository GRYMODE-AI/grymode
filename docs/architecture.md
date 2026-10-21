# Architecture

## iOS app

### Principles

- **Native SwiftUI only.** No web views, cross-platform runtimes, or duplicated frameworks.
- **Feature-oriented MVVM.** Each feature owns its views and an `@Observable` model. Shared code lives in
  `Core`, `DesignSystem`, `Domain`, and `Navigation`.
- **Swift 6 language mode.** Strict concurrency is on. UI state is `@MainActor`; networking types are `Sendable`.
- **Typed errors.** Every failure that reaches the UI is an `AppError` with a user-safe message, a retryable
  flag, and the server `request_id` when there is one.
- **Small files.** One responsibility per file; no monolithic views.

### Composition

```
GrymodeApp
 └─ AppModel (composition root, @MainActor @Observable)
     ├─ configuration: Result<AppConfiguration, AppError>   ← Info.plist ← xcconfig
     ├─ auth: AuthService (actor)                           ← Keychain session, shared refresh
     ├─ account: AccountModel                               ← sign-in state, profile sync, deletion
     ├─ apiClient: APIClient?                               ← tokens from AuthService; nil if misconfigured
     ├─ router: AppRouter                                   ← selected section + per-section NavigationPath
     └─ styleProfiles: StyleProfileStore                    ← on-device cache; backend is source of truth
RootView
 ├─ LaunchView           (phase == .launching)   ← restore Keychain session
 ├─ OnboardingFlowView   (phase == .onboarding)  ← style discovery → email code → main
 └─ MainShellView        (phase == .main)
     ├─ TabShell         horizontal size class compact → TabView
     └─ SidebarShell     horizontal size class regular → NavigationSplitView
```

`AppModel` is injected through the SwiftUI environment. Features receive only what they need.

### Adaptive layout

Layout is decided from available space, never from the device model:

- **Navigation container:** the horizontal size class chooses between a tab bar and a sidebar. iPad Slide Over
  and narrow Split View therefore get the compact tab bar automatically, as does any width at accessibility
  text sizes.
- **Content:** `AdaptiveScrollScreen` measures its container and builds an `AdaptiveLayout`:

| Width class | Container width | Horizontal margin | Readable width cap |
|-------------|-----------------|-------------------|--------------------|
| compact     | < 600 pt        | 20 pt             | none               |
| regular     | 600–959 pt      | 32 pt             | 680 pt             |
| expanded    | ≥ 960 pt        | 48 pt             | 760 pt             |

Grid content (wardrobe, looks) is capped at 1180 pt and uses 2–6 columns with a minimum cell width of 150 pt.

`AppRouter` stores navigation state outside the views, so rotation, Split View resizing, and switching between
the tab and sidebar shells preserve the selected section and each section's stack.

Every screen scrolls, so nothing clips at the largest Dynamic Type sizes. Paired choices use
`EqualWidthRow` inside `ViewThatFits`: when the two options can't sit side by side at equal width without
wrapping, they stack vertically instead. At accessibility text sizes the tab bar is used on iPad too, because a
sidebar wide enough for enlarged section names would cover the content on smaller iPads.

### Design system

- **Tokens:** `GMColor` (semantic roles over a fixed palette), `GMTextStyle`, `GMSpacing`, `GMRadius`, `GMBorder`,
  `GMSize`, `GMMotion`.
- **Components:** primary, secondary, and tertiary button styles; card; choice chip; section header; empty,
  error, and loading states; wordmark; bottom action bar.
- **Accessibility:** text colours meet WCAG AA (4.5:1) on every surface they are used on, enforced by
  `ColorContrastTests`. Tap targets are at least 44 pt. Body and control text use the system font so Dynamic
  Type scales it; display and heading fonts scale with `relativeTo:`.

### Networking

`APIClient` is the only path to the backend.

- `Endpoint<Response>` describes a call: method, `/v1` path, query, body, authentication, idempotency key,
  timeout, and retry policy.
- `RequestBuilder` adds `Accept`, `X-Request-ID`, `X-Client-Version`, `Authorization`, and `Idempotency-Key`.
  Paths outside `/v1` are rejected.
- **Retries:** exponential backoff with jitter (3 attempts, 0.5 s base, 4 s cap) for offline, timeout, 408, 429,
  and 5xx responses, and for responses the server marks `retryable`. Non-idempotent requests (`POST`, `PATCH`)
  are retried only when they carry an `Idempotency-Key`.
- **Authentication:** `AuthService` implements `AccessTokenProviding`. On a 401 the client refreshes once
  through a shared refresh task, then surfaces `unauthorized` if the refresh is rejected. Concurrent callers
  share one refresh. Sign-in uses a small hand-written Supabase GoTrue REST client (email OTP); see
  [ADR 0003](adr/0003-auth-and-data-access.md).
- **Errors:** the backend error contract `{code, message, request_id, retryable}` maps to `AppError.api`.
  Bodies that don't follow the contract (for example, a load balancer HTML page) map to a generic message.
- **Logging:** method, path, status, request ID, and duration only. Never tokens, bodies, or signed URLs.

### Persistence

Style profile and onboarding completion stay on device in `UserDefaults` as a cache (`styleProfile.v1`,
`onboardingCompleted.v1`, plus a sync flag). After sign-in the backend profile is the source of truth;
`AccountModel` pushes a pending draft and adopts remote values on restore. Sessions live in the Keychain
(`AfterFirstUnlockThisDeviceOnly`), not in UserDefaults.

## Backend

FastAPI service in `backend/`, intended for Cloud Run.

- **Auth:** verifies Supabase JWTs against JWKS (ES256 / RS256 only), issuer, audience `authenticated`, role,
  and expiry. Keys are cached and re-fetched on rotation.
- **Database:** asyncpg pool as role `grymode_api` (noinherit, member of `authenticated`). Each request sets
  `request.jwt.claims` and `role` so Postgres RLS applies; the API never bypasses RLS for user data.
- **Routes:** `GET /v1/health`, `GET|PATCH|DELETE /v1/me`, `PUT /v1/me/style-profile`. Account deletion records
  a `privacy_requests` row, hard-deletes the Auth user via the Admin API, then marks the request completed.
- **Errors:** flat JSON `{code, message, request_id, retryable}` with `X-Request-ID`. Body size capped at 64 KB.
- **Secrets:** `GRYMODE_*` settings from the environment; production values come from Secret Manager, never
  from the iOS app or source control.

Local development: `./scripts/dev-stack.sh` starts Supabase, Mailpit (sign-in emails), and uvicorn on port 8000.

### Personal try-on (MVP with AI)

- **Now:** `avatar_profiles` + `GET /v1/try-on/looks/{id}` return a `personal_2d` preview (face + wardrobe
  garments). No fabricated VR.
- **AI phase (MVP exit):** async try-on render jobs produce immersive assets; client shows RealityKit / AR
  when capable. See [ADR 0010](adr/0010-ai-and-mvp-3d-try-on.md). AI provider keys stay backend-only.

### Testing

- **Unit tests** (`GrymodeTests`): configuration, auth client, AuthService, SignInModel, AccountModel,
  AccountAPI, request building, error mapping, retry policy, adaptive layout, colour contrast, style profile
  store, router, onboarding.
- **UI tests** (`GrymodeUITests`): end-to-end against the local stack (Mailpit for codes) — sign-in, session
  recovery, sign-out and restore, account deletion, and section navigation. Launched with
  `-uiTestingResetState`. Set `TEST_RUNNER_GRYMODE_REQUIRE_STACK=1` to fail instead of skip when the stack is down.
- **Layout screenshots** (`LayoutScreenshotTests`): skipped by default. When enabled, walks every screen and
  attaches screenshots for the review in [device-test-matrix.md](device-test-matrix.md).
- **Backend:** pytest unit + integration (live local Supabase), ruff, mypy strict, pip-audit; pgTAP for RLS
  isolation (`supabase test db`).
