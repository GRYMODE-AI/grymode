# 0010. AI phase delivers MVP 3D / VR try-on

## Status

Accepted

## Context

Grymode’s MVP promise is a premium AI stylist. Rule-based outfit composition is an interim
composer. Product requires that when **real AI** is turned on for styling / generation, the
MVP also includes **full 3D / VR virtual try-on** of suggested looks on the user’s real face
and body (from the avatar profile), not only a flat collage.

## Decision

### Scope (MVP, with AI)

1. Use the existing avatar profile (height, body build, private face photo) as inputs.
2. Add an async job type (e.g. `try_on_render`) that, for an unlocked look:
   - Conditions on face + body measurements + garment images from that look.
   - Produces an immersive try-on asset (photoreal composite and/or 3D/AR-ready payload)
     via the backend AI provider — **no AI keys in the iOS binary**.
3. Client presents the result on Home / look detail:
   - Primary: immersive viewer (RealityKit / ARKit where device-capable, or full-screen
     photoreal try-on when AR body tracking is unavailable).
   - Fallback: signed try-on media URL if the device cannot run AR.
4. Gate unfinished immersive UI with a **server-controlled feature flag** until quality and
   App Review gates pass. Do not show dead “VR” chrome.

### Explicitly still post-MVP (unchanged)

- Full AI stylist **chat**, social, marketplace, and other items remaining in
  `defer_until_after_mvp` except virtual try-on / body-derived try-on inputs as above.

### Amendment to master spec sequencing

`defer_until_after_mvp` entries **Virtual try-on** and **Body scanning** are overridden for
MVP: body metrics + face are collected now; immersive try-on ships in the AI implementation
phase before MVP exit.

## Consequences

- AI provider cost, latency, and safety reviews become release gates for try-on.
- Privacy disclosures already cover face/photos; immersive media follows the same private
  Storage + deletion cascade.
- The current `personal_2d` path remains until the flag enables `immersive_3d` / `ar_vr`.
