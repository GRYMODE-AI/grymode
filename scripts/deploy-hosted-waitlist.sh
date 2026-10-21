#!/usr/bin/env bash
# Deploy waitlist table + Edge Functions + Resend secrets to the hosted project.
# Requires: supabase CLI logged in OR SUPABASE_ACCESS_TOKEN set.
#
# Create a token: https://supabase.com/dashboard/account/tokens
#   export SUPABASE_ACCESS_TOKEN=sbp_...
#   ./scripts/deploy-hosted-waitlist.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="vaojgyyhlnyzxnasmhne"
cd "$ROOT"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Set SUPABASE_ACCESS_TOKEN first (Account → Access Tokens)."
  exit 1
fi

echo "→ Linking $REF"
supabase link --project-ref "$REF" --yes

echo "→ Applying waitlist bootstrap SQL"
supabase db query --linked -f supabase/scripts/hosted_waitlist_bootstrap.sql

echo "→ Setting Resend secrets"
supabase secrets set --env-file supabase/.env --project-ref "$REF"

echo "→ Deploying Edge Functions"
supabase functions deploy waitlist-signup --project-ref "$REF"
supabase functions deploy contact-message --project-ref "$REF"

echo "→ Smoke test waitlist insert"
ANON="$(grep '^VITE_SUPABASE_ANON_KEY=' landing-page/.env | cut -d= -f2-)"
URL="$(grep '^VITE_SUPABASE_URL=' landing-page/.env | cut -d= -f2-)"
CODE=$(curl -sS -o /tmp/wl-smoke.json -w "%{http_code}" \
  -X POST "$URL/rest/v1/waitlist_signups" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d "{\"email\":\"smoke-$(date +%s)@grymode.test\",\"source\":\"smoke\"}")
echo "Insert HTTP $CODE"
cat /tmp/wl-smoke.json
echo
echo "Done. Landing page env already points at $URL"
echo "Deploy landing-page/ to Vercel with VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY."
