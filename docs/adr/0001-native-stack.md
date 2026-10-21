# 0001 — Native SwiftUI app with a FastAPI backend

- **Status:** Accepted
- **Date:** 2026-10-09

## Context

Grymode is a premium, image-heavy personal stylist for iPhone and iPad. It needs camera and photo-library
integration, StoreKit 2 subscriptions, Sign in with Apple, excellent iPad layouts, and full accessibility. AI
work (garment extraction, outfit generation) is expensive, slow, and requires provider credentials.

## Decision

- **Client:** one universal SwiftUI target, iOS 17+, Swift 6 language mode, feature-oriented MVVM with
  `@Observable`. No web views, React Native, Flutter, Capacitor, or Cordova.
- **Dependencies:** Apple frameworks first. A third-party package is added only when it removes substantial,
  risky work (Supabase Auth in Phase 2 is the expected first). No second framework may duplicate an existing
  responsibility.
- **Backend:** FastAPI on Cloud Run, Supabase Postgres with row-level security, Supabase Auth, private
  Supabase Storage, Cloud Tasks for asynchronous AI jobs, and Secret Manager for credentials.
- **Payments:** StoreKit 2 only for digital subscriptions, verified on the server. No Stripe or web checkout.
- **Project file:** Xcode synchronized folders, so adding a Swift file never requires editing `project.pbxproj`.

## Consequences

- Deep platform integration and App Store compliance, at the cost of an iOS-only client.
- All secrets and entitlement checks live on the server; the app can be inspected without exposing anything.
- Xcode 16 or later is required to open the project.
