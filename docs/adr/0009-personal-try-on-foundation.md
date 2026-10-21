# 0009. Personal try-on foundation (bridge to MVP 3D / VR)

## Status

Accepted (amended)

## Context

The original master specification listed **Virtual try-on** and **Body scanning** under
`defer_until_after_mvp`. Product direction now requires **full 3D / VR try-on in the MVP**,
delivered together with real AI processing (not as a fake client-side effect while the
composer is still rule-based).

Until the AI try-on pipeline is wired, users still need a truthful personal preview that
reuses the same fit profile.

## Decision

1. Keep the **avatar foundation** shipped now:
   - Private `avatar_profiles` (height, body build, face object in the wardrobe bucket).
   - Onboarding + Home setup for those fields.
   - `GET /v1/try-on/looks/{id}` with `preview_mode=personal_2d` as the interim composition.
2. Treat the 2D preview as a **bridge**, not the finished MVP try-on experience.
3. Full 3D / VR try-on is **MVP scope** and is implemented in the AI phase — see
   [0010](0010-ai-and-mvp-3d-try-on.md). Unfinished VR UI must stay behind a server flag.

## Consequences

- Fit profile and face capture are ready for AI conditioning.
- Copy describes a personal preview now and states that immersive try-on arrives with AI.
- Replacing `personal_2d` with `immersive_3d` / `ar_vr` does not require re-collecting avatar data.
