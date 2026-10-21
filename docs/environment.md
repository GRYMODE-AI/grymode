# Environment and configuration

## iOS build configuration

Non-secret settings flow from xcconfig files into `Info.plist`, and `AppConfiguration` reads them at launch.

| xcconfig key                       | Info.plist key              | Debug                                              | Release                   |
|------------------------------------|-----------------------------|----------------------------------------------------|---------------------------|
| `GRYMODE_ENVIRONMENT`              | `GMEnvironment`             | `development`                                      | `production`              |
| `GRYMODE_API_BASE_URL`             | `GMAPIBaseURL`              | `http://localhost:8000`                            | **empty — must be set**   |
| `GRYMODE_SUPABASE_URL`             | `GMSupabaseURL`             | `http://127.0.0.1:54321`                           | **empty — must be set**   |
| `GRYMODE_SUPABASE_PUBLISHABLE_KEY` | `GMSupabasePublishableKey`  | local CLI publishable key (public, RLS-bound)      | **empty — must be set**   |
| `GRYMODE_BUNDLE_ID`                | bundle ID                   | `com.grymode.stylist`                              | same                      |
| `DEVELOPMENT_TEAM`                 | —                           | empty                                              | **must be set**           |

Files: `ios/Config/Base.xcconfig`, `Debug.xcconfig`, `Release.xcconfig`, `Info.plist`.

### Validation rules

`AppConfiguration.load` rejects:

- an unknown environment;
- a missing or empty API URL or Supabase URL;
- any non-HTTPS URL, except `http://localhost` or `http://127.0.0.1` in the development environment;
- an empty publishable key, or a key that starts with `sb_secret_` (service keys must never ship in the app).

If validation fails, the app still launches. The Profile section reports "Not configured" and no API or
auth client is created, so no request can go to an unintended host.

> In xcconfig files, `//` starts a comment. Write URLs as `https:/$()/api.example.com`.

### Before a release build

1. Set `GRYMODE_API_BASE_URL` in `Release.xcconfig` to the production Cloud Run (or custom domain) HTTPS URL.
2. Set `GRYMODE_SUPABASE_URL` and `GRYMODE_SUPABASE_PUBLISHABLE_KEY` to the hosted Supabase project's values
   (Dashboard → Settings → API Keys → Publishable). Never put the secret / service-role key in the app.
3. Set `GRYMODE_BUNDLE_ID` to the identifier registered in App Store Connect.
4. Set `DEVELOPMENT_TEAM` to your Apple Developer Team ID.
5. Enable Sign in with Apple on that App ID (Phase 2 ships email one-time-code sign-in; SIWA is next).

The iOS app icon is already set (`Assets.xcassets/AppIcon.appiconset`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`).

### What must never be in the app

API keys, Supabase secret / service-role keys, AI provider credentials, App Store Server API private keys
(`.p8`), and signing material. The app only knows the public API base URL and the Supabase publishable key.
Row-level security protects every table; the publishable key alone grants nothing beyond what RLS allows.

`.gitignore` excludes `.env*` (except `.env.example`), `*.p8`, `*.pem`, `*.key`,
`supabase/signing_keys.json`, and `service-account*.json`.

## Local stack

One command starts Supabase (Docker), Mailpit, and the Grymode API:

```sh
./scripts/dev-stack.sh          # start (or attach to a running local Supabase)
./scripts/dev-stack.sh --reset  # re-apply migrations and seed (wipes local data)
```

| Service   | URL                         | Notes |
|-----------|-----------------------------|-------|
| Grymode API | `http://localhost:8000`   | OpenAPI docs at `/docs` in development |
| Supabase Auth / REST | `http://127.0.0.1:54321` | JWT issuer for the app |
| Mailpit   | `http://127.0.0.1:54324`    | Local inbox for sign-in codes |
| Postgres  | `127.0.0.1:54322`           | API connects as role `grymode_api` |

The simulator reaches `localhost` / `127.0.0.1` on the host. UI tests that need the stack set
`TEST_RUNNER_GRYMODE_REQUIRE_STACK=1`; without it they skip when Mailpit is unreachable.

### Backend environment variables

Prefix `GRYMODE_`. Local values live in an untracked `backend/.env` (see `backend/.env.example`).
`scripts/dev-stack.sh` exports them from `supabase status` so a `.env` file is optional for day-to-day work.

| Variable | Required | Purpose |
|----------|----------|---------|
| `GRYMODE_ENVIRONMENT` | yes | `development` / `test` / `staging` / `production` |
| `GRYMODE_SUPABASE_URL` | yes | Auth issuer base URL (HTTPS outside development) |
| `GRYMODE_SUPABASE_SECRET_KEY` | yes | Admin API key (delete user); never in the iOS app |
| `GRYMODE_DATABASE_URL` | yes | Postgres DSN as role `grymode_api` |
| `GRYMODE_RELEASE` | no | Release label in logs (default `local`) |
| `GRYMODE_LOG_LEVEL` | no | Default `INFO` |
| `GRYMODE_JWT_AUDIENCE` | no | Default `authenticated` |
| `GRYMODE_JWKS_CACHE_SECONDS` | no | Default 3600 |
| `GRYMODE_RATE_LIMIT_REQUESTS_PER_MINUTE` | no | Default 120 |
| `GRYMODE_RATE_LIMIT_DELETIONS_PER_HOUR` | no | Default 5 |
| `GRYMODE_IOS_BUNDLE_ID` | no | Default `com.grymode.stylist` (must match StoreKit / ASC) |
| `GRYMODE_STOREKIT_PRODUCT_IDS` | no | Comma-separated product IDs |
| `GRYMODE_STOREKIT_REQUIRE_SIGNED_JWS` | no | When true, reject unverified JWS (enable in staging/production with Apple keys) |

For local StoreKit purchases, the Grymode scheme uses `Grymode/Resources/Products.storekit`. Create matching
subscription products in App Store Connect before TestFlight.

### Backend commands

```sh
cd backend
uv sync --group dev
uv run ruff check . && uv run ruff format --check .
uv run mypy
uv run pytest tests/unit
# Integration (requires the local Supabase stack):
uv run pytest tests/integration
# Or force a hard fail when the stack is down:
GRYMODE_REQUIRE_INTEGRATION=1 uv run pytest tests/integration
```

Database isolation tests (pgTAP):

```sh
supabase test db
```

### Container

```sh
docker build -t grymode-api backend
docker run --rm -p 8000:8000 --env-file backend/.env grymode-api
```

Runs as uid 10001, no `Server` header, JSON logs to stdout.

## Hosted / production (still required before launch)

These are not done yet; Phase 2 verified everything against the local stack.

1. **Supabase project** — create a project, apply migrations (`supabase db push` or linked CI), set
   Auth site URL and redirect URLs, raise email rate limits for production traffic, and configure
   **custom SMTP** (the default Supabase mailer is for development only).
2. **Secret Manager** — store at least: `GRYMODE_SUPABASE_SECRET_KEY`, `GRYMODE_DATABASE_URL`
   (password for role `grymode_api`, not the Supabase postgres superuser), and later AI / StoreKit keys.
3. **Cloud Run** — deploy the image from `backend/Dockerfile`, mount secrets, set
   `GRYMODE_ENVIRONMENT=production`, HTTPS only.
4. **Apple Developer** — Team ID, bundle ID, Sign in with Apple capability, App Store Connect app record.
5. **GitHub** — push the repo so `.github/workflows/ci.yml` can run (backend + macOS iOS jobs). CI has not
   been verified on GitHub yet.

## Developer tools

Installed per user, no administrator rights needed:

| Tool | Purpose |
|------|---------|
| Xcode 16+ | Build, simulators, tests |
| swift-format | Swift formatting and linting (`.swift-format`) |
| uv, Python 3.12, ruff, mypy, pytest, pip-audit | Backend |
| Docker | Local backend container and Supabase |
| supabase CLI | Local database, migrations, RLS tests |
| gcloud | Cloud Run, Cloud Tasks, Secret Manager |
| gh, jq | Repository and scripting utilities |
