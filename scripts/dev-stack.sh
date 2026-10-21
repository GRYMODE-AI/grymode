#!/bin/zsh
# Runs the local Grymode stack for the simulator:
#   Supabase (Docker)  http://127.0.0.1:54321  auth, Postgres, storage
#   Mailpit            http://127.0.0.1:54324  where local sign-in codes are delivered
#   Grymode API        http://127.0.0.1:8000    this repository's backend/
#
# Usage: scripts/dev-stack.sh [--reset]   (--reset re-applies migrations and seed, deleting local data)
# Local values only. Deployed environments get their secrets from Google Secret Manager.
set -euo pipefail

ROOT="${0:A:h:h}"
export PATH="$HOME/.local/bin:$PATH"
cd "$ROOT"

if ! supabase status >/dev/null 2>&1; then
  echo "Starting Supabase (first run downloads several images)…"
  supabase start
fi
if [[ "${1:-}" == "--reset" ]]; then
  supabase db reset
fi

typeset -A sb
while IFS='=' read -r key value; do
  sb[$key]="${value//\"/}"
done < <(supabase status -o env)

export GRYMODE_ENVIRONMENT=development
export GRYMODE_SUPABASE_URL="${sb[API_URL]}"
export GRYMODE_SUPABASE_SECRET_KEY="${sb[SECRET_KEY]:-${sb[SERVICE_ROLE_KEY]}}"
# The API connects as the restricted grymode_api role (password set by supabase/seed.sql).
export GRYMODE_DATABASE_URL="${sb[DB_URL]/postgres:postgres@/grymode_api:grymode-local-dev-only@}"

echo "Mailpit inbox: ${sb[MAILPIT_URL]:-${sb[INBUCKET_URL]:-http://127.0.0.1:54324}}"
echo "Grymode API:   http://127.0.0.1:8000/docs"
cd backend
exec uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000
