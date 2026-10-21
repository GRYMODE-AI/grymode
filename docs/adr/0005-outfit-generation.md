# 0005. Outfit generation without inventing wardrobe items

## Status

Accepted (Phase 4)

## Context

The product needs an asynchronous outfit library built from the user's confirmed garments.
AI provider credentials may still be unavailable, and the specification forbids fabricating
outfit counts or referencing garments the user does not own.

## Decision

1. Persist outfits and `outfit_garments` under RLS; only confirmed, labelled garments are eligible.
2. Run composition as an `outfit_generation` row on `generation_jobs`, polled by the app.
3. Ship `LocalOutfitGenerator`: a deterministic composer that builds compatible combinations
   (top+bottom+shoes, dress+shoes, optional outerwear), scores, deduplicates by garment-set
   signature, and persists an accepted batch. Accepted count is always `count(*)` of persisted rows.
4. Idempotency key `outfit_gen:{wardrobe_fingerprint}` so the same confirmed set does not
   spawn duplicate billable work; a failed job can be re-queued.
5. Mark the highest-scoring look `is_free_reveal` for Phase 5 entitlement enforcement.

## Consequences

- Looks appear only after the user confirms enough wardrobe pieces.
- A vision/LLM composer can replace `LocalOutfitGenerator` without changing the API contract.
- Free-reveal locking and paywall remain Phase 5.
