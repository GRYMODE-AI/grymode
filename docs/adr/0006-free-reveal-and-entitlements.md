# 0006. Free reveal and server-enforced outfit access

## Status

Accepted (Phase 5)

## Context

Free users may view one complete look and a truthful locked-library preview. The specification
requires access checks on the server — hiding UI is not enough — and forbids returning full
locked outfit media to unauthorized clients. StoreKit purchases arrive in Phase 6.

## Decision

1. Add `public.entitlements` (no row = free). `GET /v1/me/entitlement` exposes the plan.
2. Library listing returns full garment media only for the free-reveal look (or all looks when
   premium). Locked items include title, tags, and `piece_count` only — empty `garments`, no score.
3. `GET /v1/outfits/{id}` returns 403 for locked looks without premium.
4. iOS Shows a wardrobe-ready card, free-look detail, locked tiles, and a paywall shell whose
   purchase flow waits for Phase 6.

## Consequences

- Free-reveal remains available after it is granted; premium unlocks the rest via verified
  entitlement updates later.
- Clients cannot reconstruct locked looks from the list payload.
