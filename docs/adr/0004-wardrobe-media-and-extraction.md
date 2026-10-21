# 0004 Wardrobe media and extraction

- Status: accepted
- Date: 2026-10-11

## Context

Phase 3 needs private wardrobe uploads, short-lived access to originals, an async extraction job, and an
editable garment grid the owner confirms before outfit generation. AI provider credentials may not be
available yet; the flow must still be real (no mock wardrobe) and must not claim AI detection that did not
happen.

## Decision

1. **Private Supabase Storage bucket `wardrobe`.** Objects are keyed `{user_id}/{media_id}/original.{ext}`.
   Authenticated clients have no Storage policies; the Grymode API issues signed upload and read URLs with
   the project secret key.
2. **Tables** `wardrobe_media`, `generation_jobs` (`garment_extraction`), and `garments`, all with RLS so a
   user only sees their own rows. The API continues to connect as `grymode_api` and set JWT claims per request.
3. **Upload contract:** `POST /v1/wardrobe/uploads` → client PUT to signed URL → `POST .../complete` → local
   (or later Cloud Tasks) extraction job.
4. **Local draft extractor** for development and until a vision provider is configured: one garment per photo
   with `category = uncategorised` and `user_confirmed = false`. The iOS copy asks the user to label pieces
   from their upload; it does not say an AI found them. Confirmation requires a real category.
5. **Account deletion** lists wardrobe object keys and best-effort deletes them from Storage before the Auth
   user is removed (DB rows cascade).

## Consequences

- Vision-provider extraction plugs in behind `GarmentExtractor` without changing API shapes.
- Video is photos-first in the app; frames can be uploaded as `media_type = video_frame` later.
- Hosted environments still need the `wardrobe` bucket (migration) and secret key mounted into Cloud Run.
