# 0011. OpenAI as the first AI provider (extraction + outfit composition)

## Status

Accepted

## Context

ADR 0004 and 0005 shipped rule-based adapters behind `GarmentExtractor` and `OutfitComposer`
so the API and iOS contracts could stabilise before credentials existed. The MVP needs real
garment recognition from photos and AI styling, with no provider keys in the iOS binary and no
fabricated results.

## Decision

1. `GRYMODE_AI_PROVIDER` selects adapters at startup (`local` default, `openai`). The key lives
   only in `backend/.env` locally and Secret Manager when deployed. Startup fails if `openai` is
   selected without a real key.
2. Calls use the OpenAI Responses API with strict JSON Schema Structured Outputs and
   `store: false`. Prompts, images, and model output are never logged; only token counts,
   latency-relevant codes, and counts are.
3. **Extraction** (`GRYMODE_AI_VISION_MODEL`, default `gpt-5.4-mini`): the API downloads the
   private upload server-side and sends it as a data URL (local Storage is not reachable from
   OpenAI). Up to `GRYMODE_AI_MAX_GARMENTS_PER_PHOTO` items are proposed per photo. Every
   proposal is stored **unconfirmed** for the user to review. Provider failures or "no garment
   found" produce one unlabelled draft and record a note code on the job instead of failing the
   upload.
4. **Composition** (`GRYMODE_AI_OUTFIT_MODEL`, default `gpt-6-astra`): the model receives only
   confirmed garments as short refs (`g1…gN`, never database IDs or images) plus the style
   profile in human labels. The server derives slots from categories, rejects incomplete or
   conflicting looks (one main piece; top requires one bottom; at most one shoe/outer/bag, two
   accessories), deduplicates by garment set, clamps scores, and caps at
   `MAX_ACCEPTED_OUTFITS`. If nothing passes, the job fails with `no_valid_outfits`; provider
   errors surface as their code (e.g. `ai_timeout`), never as invented looks.
5. The composer identity (`openai-v1:<model>`) is part of the generation idempotency key, so
   switching provider or model regenerates an unchanged wardrobe once.

## Consequences

- Wardrobe photos and structured wardrobe data are processed by OpenAI as a service provider;
  privacy policy and App Store disclosures name it.
- Per-call token usage is logged for cost tracking; budgets are enforced in the OpenAI project.
- `scripts/ai-smoke-test.py` exercises upload → extraction → confirm → generation against the
  local API with real photos.
- Try-on rendering (ADR 0010) will add a third adapter behind the same provider settings.
