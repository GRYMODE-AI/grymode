# 0012. AI-rendered look visuals and multi-angle personal try-on

## Status

Accepted — 2026-10-13

## Context

Looks were shown as separate garment photos, which doesn't show how the pieces read together or
how to recreate the outfit. Try-on was a 2D face + garment collage. The MVP needs a visual of each
complete look and a personal try-on the user can turn around.

## Decision

1. `outfit_renders` stores one row per `(outfit_id, kind, view)`:
   - `look` / `front`: the look's exact garments assembled on an invisible ghost mannequin.
   - `try_on` / `front`, `three_quarter`, `side`, `back`: the user wearing the look.
   Images live privately in the `wardrobe` bucket under `{user_id}/renders/{outfit_id}/`.
2. Renders use the OpenAI Images edit endpoint (`GRYMODE_AI_IMAGE_MODEL`, default
   `gpt-image-2.5-sunburst`, `GRYMODE_AI_IMAGE_QUALITY` default `high`, 1024×1536) with the user's
   own garment photos as references. Prompts list every piece and forbid adding unlisted items.
3. Look visuals are **on demand only** via `POST /v1/outfits/{id}/visual`
   (`GRYMODE_AI_RENDER_LOOKS_AFTER_GENERATION` defaults to false). Try-on renders only when the
   user opens it (`POST /v1/try-on/looks/{id}`); the front render anchors the other three angles.
   `GET` polls status. Cache hits never call OpenAI.
4. Each row carries an `input_signature`: look = `look-v3:{outfit.signature}`; try-on =
   hash(face, height, build, outfit.signature). Avatar `updated_at` is not part of the key so
   unrelated profile edits do not re-bill. In-flight rows older than 15 minutes may be re-claimed.
5. Outfit refresh **upserts by garment-set signature**, keeping outfit UUIDs so paid
   `outfit_renders` survive. Only looks absent from the new batch are deleted.
6. New image claims are counted in `usage_events` and gated by daily/monthly plan quotas before
   OpenAI is called. Failures are recorded per row (`error_code`); clients fall back to garment
   photos. Concurrency is capped by `GRYMODE_AI_IMAGE_CONCURRENCY`.
7. The iOS turntable shows the four rendered angles; the far side reuses the near-side renders
   mirrored so a drag turns the person fully round. It is image-based, not a 3D mesh.

## Consequences

- Each look visual is one image call; each try-on is four. Cost is tracked through the OpenAI
  project budget.
- The face photo is sent to OpenAI only for try-on. Render objects are included in account
  deletion and cleaned up when looks are regenerated.
- True mesh-based 3D / AR try-on would need a dedicated 3D virtual try-on provider; the render
  table and session API are designed so a provider can be swapped in behind them.
