# Full wiring checklist — real backends, AI, and App Store

Use this to move from the **local / rule-based** loop to **production-like** testing.
Nothing in the iOS app should hold AI keys, Supabase secrets, or App Store `.p8` keys.

## Honest status today

| Layer | Status |
| --- | --- |
| Auth (email OTP), profiles, wardrobe Storage, RLS | **Real** (local Supabase) |
| Looks API, free reveal, entitlements, save, Home | **Real** |
| StoreKit 2 purchase UI + sync (Xcode StoreKit Testing) | **Real locally** (JWS not crypto-verified) |
| Personal try-on 2D + avatar profile | **Real** |
| Garment extraction | **Rule-based** (`LocalDraftExtractor`) — one uncategorised draft per photo |
| Outfit generation | **Rule-based** (`LocalOutfitGenerator`) — deterministic, not LLM |
| Immersive 3D / VR try-on | **Not built** (MVP with AI — ADR 0010) |
| Hosted Supabase / Cloud Run / SIWA | **Not configured** |

Local day-to-day: `./scripts/dev-stack.sh` + Debug scheme → `127.0.0.1:8000` / `54321`.

---

## A. Accounts and platforms you must create

### 1. Apple Developer

- [ ] Apple Developer Program membership (Team ID)
- [ ] App ID / bundle ID (default in repo: `com.grymode.stylist` — change if needed)
- [ ] Capability: **Sign in with Apple** (when you want SIWA; email OTP works without it)
- [ ] App Store Connect app record
- [ ] Auto-renewable subscriptions: **Grymode Monthly** + **Grymode Yearly** (IDs must match `Products.storekit` / `GRYMODE_STOREKIT_PRODUCT_IDS`)
- [ ] Sandbox tester Apple ID
- [ ] App Store Server API key: **Issuer ID**, **Key ID**, download **`.p8`** (Secret Manager only)
- [ ] App Store Server Notifications V2 URL (after API is on HTTPS):  
  `https://<api-host>/v1/app-store/notifications`

### 2. Hosted Supabase (or keep local for AI-only tests)

- [ ] Supabase project
- [ ] Run all migrations in `supabase/migrations/`
- [ ] Auth: email OTP (+ custom SMTP for real mail)
- [ ] Copy: **Project URL**, **Publishable key**, **Secret key**
- [ ] DB password for role `grymode_api` (create/grant as in migrations + seed)
- [ ] Storage bucket `wardrobe` (created by migration) — private

### 3. Google Cloud (API hosting)

- [ ] GCP project
- [ ] Artifact Registry / Cloud Build (or your CI) to build `backend/` image
- [ ] Cloud Run service (HTTPS)
- [ ] Secret Manager secrets (below)
- [ ] Cloud Monitoring alerts (failed jobs, 5xx, AI spend — later)

### 4. AI provider (pick one primary for MVP)

Choose and create a project/key. **Backend only.**

| Option | Typical use for Grymode |
| --- | --- |
| **OpenAI** (GPT-4.1 / vision) | Label garments from photos; compose looks JSON |
| **Anthropic** (Claude + vision) | Same |
| **Google Vertex AI** / Gemini | Same; fits GCP stack |
| **Dedicated VTON vendor** (optional later) | Photoreal / 3D try-on assets |

You will need:

- [ ] Provider account + billing enabled
- [ ] API key(s) → Secret Manager (never in iOS)
- [ ] Model IDs for: (a) vision labeling, (b) outfit composition, (c) try-on render when ready
- [ ] Monthly budget / rate limits agreed
- [ ] Decision: sync in-process workers vs **Cloud Tasks** queue (recommended before scale)

---

## B. Secrets and config to provide (fill and share securely)

Do **not** paste secrets into chat. Put them in 1Password / Secret Manager and give the agent
**names of secrets** + non-secret IDs, or a filled private `.env` on your machine only.

### Backend (`GRYMODE_*` — see `backend/.env.example`)

| Variable | What you provide |
| --- | --- |
| `GRYMODE_ENVIRONMENT` | `staging` then `production` |
| `GRYMODE_SUPABASE_URL` | Hosted `https://….supabase.co` |
| `GRYMODE_SUPABASE_SECRET_KEY` | Supabase secret / service role |
| `GRYMODE_DATABASE_URL` | `postgresql://grymode_api:…@…:5432/postgres` (SSL) |
| `GRYMODE_IOS_BUNDLE_ID` | Exact ASC bundle ID |
| `GRYMODE_STOREKIT_PRODUCT_IDS` | Comma-separated product IDs |
| `GRYMODE_STOREKIT_REQUIRE_SIGNED_JWS` | `true` only after Apple JWS verify is implemented |
| `GRYMODE_AI_PROVIDER` | `openai` (or `local` for rule-based, no external calls) |
| `GRYMODE_AI_API_KEY` | OpenAI project key (Secret Manager) |
| `GRYMODE_AI_VISION_MODEL` | Extraction model, default `gpt-5.4-mini` |
| `GRYMODE_AI_OUTFIT_MODEL` | Composition model, default `gpt-6-astra` |
| *(to add)* `GRYMODE_AI_TRYON_MODEL` or vendor endpoint | When immersive try-on lands |
| *(to add)* App Store Server API: issuer, key id, `.p8` path/secret | For production receipts |

### iOS Release (`ios/Config/Release.xcconfig`)

| Key | What you provide |
| --- | --- |
| `GRYMODE_API_BASE_URL` | `https:/$()/api.yourdomain.com` |
| `GRYMODE_SUPABASE_URL` | Hosted Supabase URL |
| `GRYMODE_SUPABASE_PUBLISHABLE_KEY` | Publishable only |
| `DEVELOPMENT_TEAM` | Apple Team ID |
| `GRYMODE_BUNDLE_ID` | If not `com.grymode.stylist` |

### Legal / support (App Review)

| Item | What you provide |
| --- | --- |
| Live Privacy URL | Host `docs/legal/privacy-policy.md` at `https://grymode.ai/privacy` (or your domain) |
| Live Terms URL | Same for `/terms` — update `LegalLinks` if domain differs |
| Support inbox | `support@…` that receives mail |

---

## C. What we will implement once credentials exist

### Phase W1 — Hosted stack (no AI yet)

1. Point Release xcconfig + Cloud Run at hosted Supabase  
2. Apply migrations; verify OTP email via real SMTP  
3. Smoke: sign-in → upload → confirm → generate looks (still **rule-based**) → subscribe (sandbox)  
4. Demo seed against hosted DB (`scripts/seed-demo-account.py` adapted)

### Phase W2 — Real AI looks (replaces local adapters) — **done locally (ADR 0011)**

Verify any time with `python3 scripts/ai-smoke-test.py <photo.jpg> --confirm --generate`.

1. Add provider client behind existing protocols (`GarmentExtractor`, `OutfitComposer`)  
2. Wire `main.py` to choose Local* vs AI* via `GRYMODE_AI_PROVIDER`  
3. Structured JSON schemas + validation (no fabricated counts)  
4. Job stages / timeouts / spend logging  
5. Re-test wardrobe → looks with **real clothing photos**

### Phase W3 — Production StoreKit verification

1. Verify JWS with Apple root certs / App Store Server Library  
2. Enable `GRYMODE_STOREKIT_REQUIRE_SIGNED_JWS=true`  
3. ASSN V2 endpoint end-to-end in sandbox  

### Phase W4 — Immersive try-on (MVP with AI — ADR 0010)

1. Job type `try_on_render` using avatar face + body + look garments  
2. Persist private try-on media; return URLs / AR payload  
3. iOS RealityKit / ARKit viewer when device supports it  
4. Server feature flag until quality gate passes  

---

## D. API surface already built (no new CRUD needed for core loop)

These are already implemented; they need a **live API host + real adapters**, not new endpoints for the basic journey:

- `/v1/health`, `/v1/me*`, wardrobe uploads/jobs/garments  
- `/v1/outfits*`, `/v1/home`, saved looks  
- `/v1/me/avatar*`, `/v1/try-on/looks/{id}`  
- `/v1/subscriptions/*`, `/v1/app-store/notifications`  

New endpoints only when AI try-on / job polling for `try_on_render` is added.

---

## E. Recommended path for this project: **A — Local + real AI first**

Step-by-step account setup: [how-to-obtain-credentials.md](how-to-obtain-credentials.md).

If you want **real AI looks while still on Docker/local Supabase**:

1. AI provider choice + API key (in `backend/.env`, not chat)
2. Preferred vision + composition model names
3. Confirm budget (e.g. $X/month for dev)
4. Say “wire AI on local first”

We can keep Debug app → `127.0.0.1:8000` and swap only `LocalDraftExtractor` / `LocalOutfitGenerator` for AI adapters — **no Cloud Run required for that step**.

---

## F. What “fake” remains until you provide the above

- Garment labels: OpenAI vision when `GRYMODE_AI_PROVIDER=openai` (user still reviews + confirms)  
- Looks: OpenAI composition + server validation when `GRYMODE_AI_PROVIDER=openai`
- Look visuals / try-on: on-demand only; refresh upserts by signature so paid renders survive; daily/monthly image quotas in `usage_events`  
- Try-on: face + garment collage, not 3D/VR  
- StoreKit in production: unsigned JWS path must not be used with `REQUIRE_SIGNED_JWS=true` until W3  
- Release iOS build: empty Release xcconfig → app reports Not configured  

---

## Quick reply template (copy/paste)

```
Apple Team ID: …
Bundle ID: …
ASC Monthly product ID: …
ASC Yearly product ID: …

Supabase URL: …
(Publishable + secret: in Secret Manager / local .env only)

API base URL (or “local only for now”): …

AI provider: openai | anthropic | vertex
AI key: (in backend/.env as GRYMODE_AI_API_KEY)
Vision model: …
Outfit model: …
Monthly AI budget: …

Legal domain for privacy/terms: …
Support email: …

Start with: local+AI | hosted no-AI | full production
```
