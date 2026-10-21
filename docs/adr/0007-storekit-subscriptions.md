# 0007. StoreKit 2 subscriptions with server entitlements

## Status

Accepted (Phase 6)

## Context

Premium library access must follow a verified App Store purchase. The backend already gates outfit
media behind `entitlements.plan`. Phase 6 wires StoreKit 2 and a sync path without trusting the client.

## Decision

1. Offer `com.grymode.stylist.premium.monthly` and `.yearly` (mirrored in `Products.storekit` for Xcode testing).
2. After purchase/restore, the app sends the StoreKit 2 JWS (`signed_transaction`) to
   `POST /v1/subscriptions/sync`. The API validates bundle id + product allowlist, records a
   `subscriptions` row, and refreshes `entitlements`.
3. Accept Xcode StoreKit Testing / structural JWS checks in development and test only. Staging and
   production set `GRYMODE_STOREKIT_REQUIRE_SIGNED_JWS=true` once App Store Server Library credentials
   are configured (full cryptographic verification).
4. `POST /v1/app-store/notifications` ingests App Store Server Notifications V2 and reconciles known
   `original_transaction_id` rows.
5. Paywall shows StoreKit localized prices, Restore Purchases, Terms/Privacy/Manage links.

## Consequences

- Local testing uses the StoreKit Configuration file (enable it on the Grymode scheme in Xcode).
- Hosted environments need Apple API keys before requiring signed JWS.
- Free reveal remains available regardless of subscription state.
