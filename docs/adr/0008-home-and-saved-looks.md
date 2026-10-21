# 0008. Home, today's look, and saved looks

## Status

Accepted (Phase 7)

## Context

Phase 7 delivers the premium core loop: Home with a daily look, a filterable full library,
outfit detail, and save/unsave. Wardrobe management already exists from earlier phases.

## Decision

1. Add `public.saved_looks` with owner RLS and `grymode_api` grants. Save requires the caller
   to be entitled to open that outfit (free reveal or premium).
2. Expose `GET /v1/home` with a deterministic **today's look**: free users receive the free
   reveal; premium users rotate among all accepted outfits using `sha256(user_id:UTC-date)`.
3. Extend `GET /v1/outfits` with optional `occasion` and `saved_only` filters, plus
   `filter_occasions`, `saved_count`, and per-outfit `is_saved`.
4. Add `POST/DELETE /v1/outfits/{id}/save`. iOS Home and Looks consume these endpoints; detail
   sheets toggle save without leaving the library context.

## Consequences

- Today's look needs no extra table; the pick is stable for a UTC calendar day.
- Locked looks remain non-savable until entitlement unlocks them.
- Category filters on Looks mean occasion tags from the generated library, not garment categories.
