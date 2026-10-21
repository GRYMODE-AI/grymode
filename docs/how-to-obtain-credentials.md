# How to obtain every credential Grymode needs

**Recommended path for this project: Path A — Local stack + real AI first.**

Keep using `./scripts/dev-stack.sh` and the Debug iOS scheme (`127.0.0.1`). Replace rule-based
extraction/outfit generation with a real vision/LLM provider. Only after looks quality is good,
move to hosted Supabase + Cloud Run (Path B) and production StoreKit crypto (Path C).

Why Path A fits Grymode:

- The master spec requires **real AI processing**, not simulated counts.
- Auth, Storage, RLS, jobs, entitlements, and StoreKit Testing already work locally.
- You can iterate on AI cost/quality without waiting on Apple Team ID or Cloud Run.
- Immersive try-on (ADR 0010) builds on the same AI backend once looks are real.

Never put AI keys, Supabase secrets, or App Store `.p8` files in the iOS app or in chat.

---

## Path A — what you need first (minimum)

| Item | Required for Path A? |
| --- | --- |
| AI provider account + API key | **Yes** |
| Vision + outfit model names | **Yes** |
| Local Docker + Supabase (already) | Yes |
| Hosted Supabase / Cloud Run | No (later) |
| Apple Team ID / ASC products | No for AI looks; yes before TestFlight |
| App Store Server `.p8` | No until production receipt verify |

---

## 1. AI provider (do this first)

Pick **one** primary provider. Strong default for this stack: **OpenAI** (vision + structured JSON)
or **Anthropic** (Claude vision). If you are all-in on GCP already, use **Vertex AI / Gemini**.

### 1a. OpenAI

1. Go to [https://platform.openai.com](https://platform.openai.com) and sign in / create an org.
2. Add a payment method: **Settings → Billing**.
3. Set a monthly budget / usage limit under Billing so a bad loop cannot run away.
4. Create a key: **API keys → Create new secret key**.  
   Copy it once into a password manager. You will put it only in `backend/.env` as something like
   `GRYMODE_AI_API_KEY=sk-…` (exact name lands when we wire the client).
5. Note model IDs you want to use (examples — confirm current names in the dashboard):
   - Vision / garment labeling: a current GPT-4.1 or GPT-4o vision-capable model  
   - Outfit composition: same family or a stronger reasoning model if you split roles  
6. Optional: create a separate **project** named `grymode-dev` vs `grymode-prod` with different keys.

### 1b. Anthropic

1. Go to [https://console.anthropic.com](https://console.anthropic.com).
2. Enable billing.
3. **API keys → Create Key**. Store in the password manager → local `backend/.env` only.
4. Note a current Claude model with vision (e.g. Claude Sonnet / Opus — check console for exact id).

### 1c. Google Vertex AI / Gemini

1. Create or select a [Google Cloud](https://console.cloud.google.com) project.
2. Enable **Vertex AI API** (and billing).
3. Create a service account with Vertex AI User; download JSON key → Secret Manager / local path
   **never committed** (already gitignored patterns cover `service-account*.json`).
4. Note project id, region (e.g. `us-central1`), and Gemini model id.

### What to write down for the agent (non-secret)

```
AI provider: openai | anthropic | vertex
Vision model id: …
Outfit model id: …
Key location: backend/.env (GRYMODE_AI_API_KEY set locally — do not paste here)
Monthly budget: $…
```

---

## 2. Confirm local Grymode stack (you likely already have this)

1. Install Docker Desktop and [Supabase CLI](https://supabase.com/docs/guides/cli).
2. From the repo root:

```sh
./scripts/dev-stack.sh
```

3. Verify:
   - API: `http://127.0.0.1:8000/v1/health`
   - Mailpit OTP inbox: `http://127.0.0.1:54324`
   - Supabase API: `http://127.0.0.1:54321`
4. Optional demo data: `./scripts/seed-demo-account.sh`
5. iOS: Debug scheme, API base `http://127.0.0.1:8000` (see `ios/Config/Debug.xcconfig`).

No new accounts required for Path A beyond AI.

---

## 3. Apple Developer (needed before TestFlight / Path C — gather when ready)

### 3a. Team and App ID

1. Enroll at [https://developer.apple.com/programs](https://developer.apple.com/programs).
2. Note **Team ID**: Membership details (10-character string).
3. Certificates, Identifiers & Profiles → **Identifiers → App IDs → Register**.
   - Bundle ID: match repo default `com.grymode.stylist` or your chosen id.
4. Enable capability **Sign in with Apple** on that App ID (can wait; email OTP works without it).
5. Put Team ID into `ios/Config/Base.xcconfig` as `DEVELOPMENT_TEAM = YOURTEAMID`.

### 3b. App Store Connect app + subscriptions

1. [https://appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **+**.
2. Create the iOS app with the same bundle ID.
3. **Subscriptions** (or Monetization → Subscriptions):
   - Create a subscription group (e.g. “Grymode Access”).
   - Add products matching `ios/Grymode/Resources/Products.storekit` (open the file in Xcode for
     exact product IDs — typically monthly + yearly).
   - Fill pricing, localizations, review screenshot if ASC asks.
4. Create a **Sandbox Apple ID**: Users and Access → Sandbox → Testers.
5. On a device/simulator signed into that sandbox account, purchases hit sandbox.

### 3c. App Store Server API key (production receipt verify — Path C)

1. App Store Connect → Users and Access → **Integrations → In-App Purchase** (or Keys).
2. Generate an **In-App Purchase** key → download the `.p8` **once**.
3. Record: **Issuer ID**, **Key ID**, and store the `.p8` in Secret Manager / a private folder
   outside git (patterns like `*.p8` are gitignored).
4. Later: App Store Server Notifications V2 → Production/Sandbox URL  
   `https://<your-api-host>/v1/app-store/notifications`.

### What to write down

```
Team ID: …
Bundle ID: …
Monthly product ID: …
Yearly product ID: …
Sandbox tester email: … (password in your vault)
App Store Issuer ID / Key ID: … (.p8 in vault only)
```

---

## 4. Hosted Supabase (Path B — after local AI looks good)

1. [https://supabase.com/dashboard](https://supabase.com/dashboard) → New project (region near users).
2. Save the **database password** immediately.
3. **Settings → API**:
   - Project URL → `GRYMODE_SUPABASE_URL`
   - Publishable (anon) key → iOS Release xcconfig only
   - Secret key → backend / Secret Manager only
4. Link CLI / push migrations from this repo:

```sh
supabase link --project-ref <ref>
supabase db push
```

5. Auth → Providers: Email on; configure **custom SMTP** (Resend, Postmark, SES, etc.) so OTP
   works outside Mailpit.
6. Ensure Storage bucket `wardrobe` exists (created by migrations) and stays **private**.
7. Create/login role `grymode_api` with the password your production `GRYMODE_DATABASE_URL` uses
   (mirror local seed pattern; never use the `postgres` superuser for the API).

### What to write down

```
Supabase URL: https://xxxx.supabase.co
Publishable key: (vault → Release.xcconfig)
Secret key: (vault → backend .env / Secret Manager)
Database URL for grymode_api: (vault)
SMTP provider: …
```

---

## 5. Google Cloud Run (Path B — API hosting)

1. [https://console.cloud.google.com](https://console.cloud.google.com) → create/select project.
2. Enable billing; enable **Cloud Run**, **Secret Manager**, **Artifact Registry** (and Vertex if chosen).
3. Create secrets for each `GRYMODE_*` value (and AI key).
4. Build and deploy the `backend/` Docker image (see `docs/environment.md` Container section).
5. Cloud Run service:
   - HTTPS URL → `GRYMODE_API_BASE_URL` in Release xcconfig  
   - Env from Secret Manager  
   - Min instances 0 or 1 depending on cold-start tolerance  
6. Optional custom domain + managed cert.

### What to write down

```
Cloud Run URL: https://…
GCP project id: …
Secrets names: grymode-supabase-secret, grymode-database-url, grymode-ai-key, …
```

---

## 6. Legal and support (before App Review)

1. Choose production domain (e.g. `grymode.ai`).
2. Host rendered pages from `docs/legal/privacy-policy.md` and `terms-of-use.md` at:
   - `https://<domain>/privacy`
   - `https://<domain>/terms`
3. If the domain is not `grymode.ai`, update `ios/Grymode/Core/Legal/LegalLinks.swift`.
4. Create mailbox `support@<domain>` (Google Workspace, Fastmail, etc.).
5. Point Profile “Contact support” (`mailto:`) at that address.

---

## 7. Where each secret lives

| Secret | iOS app | `backend/.env` local | GCP Secret Manager | Chat / git |
| --- | --- | --- | --- | --- |
| Supabase publishable | Yes (Release) | No | Optional | No |
| Supabase secret | **Never** | Yes | Yes | **Never** |
| AI API key | **Never** | Yes | Yes | **Never** |
| DB password | **Never** | Yes | Yes | **Never** |
| App Store `.p8` | **Never** | Path or secret | Yes | **Never** |
| API base URL | Yes | n/a | n/a | OK |

Local template: `backend/.env.example` → copy to `backend/.env` (gitignored).

---

## 8. Suggested sequence (aligned with Grymode)

| Step | Action | Blocked on |
| --- | --- | --- |
| **1** | Create AI account, billing, key in `backend/.env` | You |
| **2** | Tell the agent: provider + model ids + “wire AI on local” | You |
| **3** | We implement AI adapters; you test with real wardrobe photos | Us + you |
| **4** | Create Apple Team + ASC subscriptions | You |
| **5** | Host Supabase + Cloud Run; fill Release xcconfig | You |
| **6** | Wire StoreKit crypto + ASSN | Us + Apple keys |
| **7** | Immersive try-on (ADR 0010) behind flag | AI try-on model/vendor |
| **8** | Host legal pages; TestFlight | You |

---

## 9. Copy-paste reply when Path A is ready

```
Path: A (local + real AI)

AI provider: openai | anthropic | vertex
Vision model: <id>
Outfit model: <id>
GRYMODE_AI_API_KEY: set in backend/.env on my machine (not pasted)
Monthly budget: $<amount>

Proceed to wire AI extractors/composers on local stack.
```

When you later want Path B/C, add Team ID, product IDs, Supabase URL, and Cloud Run URL using the
sections above.
