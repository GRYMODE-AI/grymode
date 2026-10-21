# Data retention and deletion

What Grymode stores, where, for how long, and how it is deleted. Update this document whenever a table,
bucket, log, or third-party processor is added.

## What is stored today (Phase 4)

| Data | Where | Retention | Deleted by |
|------|-------|-----------|------------|
| Email address, auth identities, sessions | Supabase Auth (`auth.users`, `auth.sessions`, `auth.refresh_tokens`) | Until the account is deleted | Account deletion (admin API hard delete) |
| Display name, style profile, onboarding date | `public.profiles` | Until the account is deleted | Cascade from `auth.users` |
| Wardrobe originals | Supabase Storage bucket `wardrobe` (private) + `public.wardrobe_media` | Until piece/account deletion | Account deletion (Storage cleanup then Auth delete); garment delete best-effort removes object |
| Garment metadata and confirmation flags | `public.garments` | Until piece/account deletion | Cascade / explicit delete |
| Extraction and outfit-generation jobs | `public.generation_jobs` | Until account deletion | Cascade from `auth.users` |
| Outfit looks and garment membership | `public.outfits`, `public.outfit_garments` | Until account deletion (or replaced by a new generation for the same wardrobe fingerprint) | Cascade / replace-on-generate |
| Subscription ledger (transaction ids, product, status, expiry; JWS hash only) | `public.subscriptions` | Until account deletion | Cascade from `auth.users` |
| Access plan | `public.entitlements` | Until account deletion / plan change | Upserted by subscription sync |
| Account deletion record: user ID (no FK), type, status, timestamps | `public.privacy_requests` | 2 years after completion, as proof of the request being honoured | Scheduled purge (still to add) |
| Session tokens on device | iOS Keychain, this device only, not backed up | Until sign-out, account deletion, or rejected refresh | App |
| Style profile draft on device | iOS `UserDefaults` | Until sign-out or account deletion | App |
| Request logs | Cloud Logging (stdout JSON) | Cloud Logging default (30 days) | Automatic expiry |

Request logs contain method, route template, status, latency, request ID, and error types. They never contain
tokens, email addresses, request bodies, signed URLs, or images.

## Account deletion

Entry point: **Profile > Account > Delete account**. The screen explains what is deleted and that an App
Store subscription is not cancelled. It links to subscription management and requires explicit
confirmation. The server:

1. records a `privacy_requests` row;
2. deletes wardrobe objects from the private Storage bucket (best effort);
3. hard-deletes the auth user, which revokes all sessions and cascades to every user-owned table;
4. marks the request completed.

The app then removes the Keychain session and the on-device style profile and returns to the welcome screen.

Planned additions before launch:

- Cancel or orphan-proof in-flight generation jobs on account deletion.
- Revoke Sign in with Apple tokens (when Sign in with Apple is added).
- A reconciliation job that retries `processing` deletion requests older than one hour.
- Purge orphaned Storage objects if a garment delete's Storage call failed.

## Model training

Wardrobe images are not used to train models. Using them would need a separate, explicit, opt-in consent
mechanism that has been designed and approved.
