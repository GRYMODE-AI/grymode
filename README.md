# Grymode AI Stylist

A native iOS and iPadOS personal stylist. People photograph or film their wardrobe, confirm the pieces Grymode
detects, and receive a library of complete outfits built only from clothes they own.

- **App:** SwiftUI, iOS 17+, one universal target for iPhone and iPad (`ios/`).
- **Backend:** FastAPI on Cloud Run (local Docker / uvicorn today), Supabase Postgres / Auth / Storage,
  Cloud Tasks and Secret Manager for production (`backend/`, `supabase/`).

## Repository layout

```
ios/
  Config/                 xcconfig files and Info.plist (non-secret build configuration)
  Grymode/                App source (Xcode synchronized folder; new files are picked up automatically)
    App/                  Composition root, app entry point, preview support
    Core/                 Configuration, auth, networking, errors, logging
    DesignSystem/         Tokens, reusable components, adaptive layout
    Domain/               Models and on-device stores
    Features/             One folder per feature (Auth, Onboarding, Home, Style, Wardrobe, Looks, Profile)
    Navigation/           Router and the adaptive tab / sidebar shell
    Resources/            Fonts and asset catalog
  GrymodeTests/           Unit tests
  GrymodeUITests/         UI tests (including end-to-end against the local stack)
backend/                  FastAPI service (uv, Python 3.12)
supabase/                 Migrations, RLS, pgTAP, Auth templates, local config
landing-page/             Pre-launch waitlist site (Vite + React + Tailwind; deploy to Vercel)
                          Waitlist → Supabase Edge Function + Resend email + Storage backup (see docs/waitlist.md)
scripts/dev-stack.sh      Starts local Supabase + Mailpit + the Grymode API
docs/                     Architecture, decisions (ADRs), environment, device matrix, licences
```


## Requirements

- macOS with Xcode 16 or later (the project uses synchronized folders, project format 77).
- Docker Desktop (for local Supabase).
- An iOS 17+ simulator or device.

## Getting started

```sh
# Terminal 1 — local Auth, Postgres, Mailpit, and the Grymode API
./scripts/dev-stack.sh

# Terminal 2 — open the app
open ios/Grymode.xcodeproj
```

Choose the **Grymode** scheme and any iPhone or iPad simulator, then run. Debug builds talk to
`http://localhost:8000` and the local Supabase at `http://127.0.0.1:54321`. Sign-in codes arrive in
Mailpit at `http://127.0.0.1:54324`.

See [docs/environment.md](docs/environment.md) for configuration keys, backend variables, and the values that
must be set before a release build.

## Command line

```sh
cd ios

# Build
xcodebuild build -project Grymode.xcodeproj -scheme Grymode \
  -destination 'platform=iOS Simulator,name=iPhone 17e'

# Unit tests
xcodebuild test -project Grymode.xcodeproj -scheme Grymode \
  -destination 'platform=iOS Simulator,name=iPhone 17e' -only-testing:GrymodeTests

# End-to-end UI tests (requires ./scripts/dev-stack.sh)
TEST_RUNNER_GRYMODE_REQUIRE_STACK=1 xcodebuild test -project Grymode.xcodeproj -scheme Grymode \
  -destination 'platform=iOS Simulator,name=iPhone 17e' -only-testing:GrymodeUITests/GrymodeUITests

# Formatting
swift-format lint --recursive --configuration ../.swift-format Grymode GrymodeTests GrymodeUITests
```

```sh
cd backend
uv sync --group dev
uv run ruff check . && uv run mypy && uv run pytest
```

Simulator names depend on the installed runtimes; list them with `xcrun simctl list devices available`.

## Security principles

- The app contains no secrets. AI provider keys and service credentials live only on the backend, in Google
  Secret Manager for production.
- Subscription entitlements are verified by the backend; the app never trusts a local flag.
- Wardrobe media is stored in private buckets and accessed through short-lived signed URLs.
- Logs never include wardrobe images, signed URLs, tokens, or personal data.
- Account deletion is real (not just sign-out): the auth user is hard-deleted and every user-owned row
  cascades; the UI explains that an App Store subscription is not cancelled.

## Documentation

- [Architecture](docs/architecture.md)
- [Environment and configuration](docs/environment.md)
- [Data retention and deletion](docs/data-retention.md)
- [Device test matrix](docs/device-test-matrix.md)
- Decisions: [0001 Native stack](docs/adr/0001-native-stack.md),
  [0002 Typography and light appearance](docs/adr/0002-typography-and-light-appearance.md),
  [0003 Auth and data access](docs/adr/0003-auth-and-data-access.md),
  [0004 Wardrobe media and extraction](docs/adr/0004-wardrobe-media-and-extraction.md),
  [0005 Outfit generation](docs/adr/0005-outfit-generation.md),
  [0006 Free reveal and entitlements](docs/adr/0006-free-reveal-and-entitlements.md),
  [0007 StoreKit subscriptions](docs/adr/0007-storekit-subscriptions.md),
  [0008 Home and saved looks](docs/adr/0008-home-and-saved-looks.md),
  [0009 Personal try-on foundation](docs/adr/0009-personal-try-on-foundation.md),
  [0010 AI and MVP 3D try-on](docs/adr/0010-ai-and-mvp-3d-try-on.md)

Privacy / review: [Privacy disclosures](docs/privacy-disclosures.md),
[Review demo account](docs/review-demo.md),
[Release checklist](docs/release-checklist.md),
[Wiring checklist (AI + hosted)](docs/wiring-checklist.md),
[How to obtain credentials](docs/how-to-obtain-credentials.md),
[Privacy policy draft](docs/legal/privacy-policy.md),
[Terms draft](docs/legal/terms-of-use.md).

## Status

**Phase 8 (account, privacy, review readiness)** is in progress. **MVP try-on:** fit profile +
2D personal preview are live now; **full 3D / VR try-on is MVP scope and ships with the AI
implementation phase** (ADR 0010), not deferred after MVP. Host `grymode.ai/privacy` and
`/terms` before App Store submission. Enable `Products.storekit` for local purchases. Sign in
with Apple and Cloud Run hosting still wait on your Apple / GCP accounts.
