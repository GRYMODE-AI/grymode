# App Review / demo account

## Credentials

| Field | Value |
| --- | --- |
| Email | `review@grymode.test` |
| Password (admin-set) | `GrymodeReview!2026` |
| App sign-in | Email OTP (Mailpit locally). Hosted review builds may use password grant if enabled. |

## What the seed includes

`./scripts/seed-demo-account.sh` (Python) creates:

- Confirmed onboarding + style profile
- **Premium** entitlement (demo)
- **8** confirmed garments (solid placeholder PNGs in private Storage)
- **9** deterministic looks (one free reveal)
- Avatar height/build for try-on setup (add a face photo in-app for personal preview)

## Local setup

1. `./scripts/dev-stack.sh`
2. `./scripts/seed-demo-account.sh`
3. Sign in with `review@grymode.test` — OTP appears in Mailpit (`http://127.0.0.1:54324`)
4. Home → today’s look; Looks → full library; Profile → Legal & support

## App Store Connect review notes

See paste block in [release-checklist.md](release-checklist.md).
