# Grymode AI — Pre-launch landing page

Standalone React (Vite + TypeScript + Tailwind) marketing site for waitlist signups.
Independent from the SwiftUI app and FastAPI backend; only shares brand tokens, copy, and
a Supabase waitlist table.

## Local development

```bash
cd landing-page
cp .env.example .env   # fill VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

### Waitlist (Supabase + Resend + backup)

Signups go through the `waitlist-signup` Edge Function, which:

1. Stores the email in `public.waitlist_signups`
2. Writes a JSON backup to Storage bucket `waitlist-backups`
3. Sends a welcome email via Resend

```bash
# From repo root — apply table + backup bucket migrations
supabase migration up --local

# Secrets (Resend) — never put these in landing-page/.env
cp supabase/.env.example supabase/.env
# edit RESEND_API_KEY and RESEND_FROM_EMAIL

supabase functions serve waitlist-signup --env-file supabase/.env
```

Hosted:

```bash
supabase db push
supabase functions deploy waitlist-signup
supabase secrets set --env-file supabase/.env
```

Full details: [`docs/waitlist.md`](../docs/waitlist.md).

Table: `public.waitlist_signups` — anon can **insert** only; no public reads. Resend + Storage use the service role inside the Edge Function.

## Build

```bash
npm run build
npm run preview
```

## Vercel

1. Import this Git repository.
2. Set **Root Directory** to `landing-page`.
3. Add env vars `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (production anon key).
4. Deploy. Framework preset: Vite (`vercel.json` included).
5. Separately deploy `waitlist-signup` and set Resend secrets on the Supabase project (not on Vercel).

## Brand

Fonts (OFL): Oranienbaum + Unna under `public/fonts/`.
Palette matches the iOS design system (`#F5F3EF`, `#1A1A1A`, `#6B6B4B`).
Hero line matches the app Welcome screen: *Your wardrobe has more to say.*

## Refreshing app screenshots

`public/images/app-{home,wardrobe,looks}.png` are captured from the seeded local account
(with a filled wardrobe and look library), not the empty Phase-1 layout matrix.
After recapture, rebuild (`npm run build`) so `dist/` picks up the new files — `vite preview` serves `dist/`, not `public/` live.

With the local stack running and a simulator available:

```bash
cd ios
TEST_RUNNER_GRYMODE_LANDING_SHOTS=1 \
TEST_RUNNER_GRYMODE_SHOT_DIR="$(pwd)/../landing-page/public/images" \
TEST_RUNNER_GRYMODE_REQUIRE_STACK=1 \
xcodebuild test -project Grymode.xcodeproj -scheme Grymode \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -derivedDataPath ../build/DerivedData \
  -only-testing:GrymodeUITests/LandingPageScreenshotTests \
  -parallel-testing-enabled NO
```
