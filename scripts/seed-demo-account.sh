#!/bin/zsh
# Seeds the App Review demo Auth user with wardrobe + deterministic looks (local Supabase).
set -euo pipefail
ROOT="${0:A:h:h}"
export PATH="$HOME/.local/bin:$PATH"
cd "$ROOT"
exec python3 scripts/seed-demo-account.py "$@"
