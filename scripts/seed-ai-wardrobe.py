#!/usr/bin/env python3
"""Reset a local account's wardrobe and fill it with a varied menswear capsule via the real AI flow.

Local stack only. For each catalogue item a product photo is generated once with the configured
OpenAI image model and cached in artifacts/ai-wardrobe/. The photos are then uploaded through the
Grymode API exactly like the iOS app (AI extraction -> confirm -> generate looks), and the script
waits for the styled look visuals to render.

The account's avatar (height, build, face photo), profile, and entitlement are kept. A session is
minted with the local admin API (magic link), so the account password is never needed or changed.

Usage:
    scripts/seed-ai-wardrobe.py --email you@example.com
    scripts/seed-ai-wardrobe.py --email you@example.com --skip-reset --no-wait-renders
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module

smoke = import_module("ai-smoke-test")

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "artifacts" / "ai-wardrobe"
DB_CONTAINER = os.environ.get("GRYMODE_DB_CONTAINER", "supabase_db_grymode")

# slug, description used for the product photo
CATALOGUE: list[tuple[str, str]] = [
    ("white-oxford-shirt", "crisp white cotton oxford button-down shirt, long sleeves, button-down collar"),
    ("light-blue-linen-shirt", "light sky-blue linen shirt, long sleeves, relaxed fit, spread collar"),
    ("white-crew-tee", "plain white heavyweight cotton crew-neck t-shirt"),
    ("black-crew-tee", "plain black cotton crew-neck t-shirt"),
    ("navy-pique-polo", "navy blue cotton pique polo shirt with three-button placket"),
    ("olive-camp-shirt", "olive green short-sleeve camp-collar shirt in textured cotton"),
    ("camel-merino-crewneck", "camel merino wool crew-neck sweater, fine knit"),
    ("charcoal-quarter-zip", "charcoal grey wool quarter-zip knit pullover"),
    ("cream-cable-knit", "cream chunky cable-knit wool crew-neck sweater"),
    ("navy-blazer", "unstructured navy blue wool two-button blazer with patch pockets"),
    ("tan-trench-coat", "classic tan cotton gabardine double-breasted trench coat with belt"),
    ("black-leather-jacket", "black leather minimalist rider jacket with silver zips"),
    ("olive-field-jacket", "olive green cotton field jacket with four front pockets"),
    ("dark-indigo-jeans", "dark indigo raw denim slim straight jeans"),
    ("light-wash-jeans", "light-wash blue denim straight-leg jeans"),
    ("beige-chinos", "beige cotton twill slim chinos"),
    ("charcoal-wool-trousers", "charcoal grey wool tailored trousers with pressed crease"),
    ("black-tailored-trousers", "black slim tailored trousers"),
    ("olive-cargo-pants", "olive green relaxed cotton cargo pants"),
    ("navy-chino-shorts", "navy blue cotton chino shorts, 7 inch inseam"),
    ("white-leather-sneakers", "pair of minimalist white leather low-top sneakers"),
    ("brown-suede-chelsea-boots", "pair of dark brown suede chelsea boots"),
    ("black-penny-loafers", "pair of polished black leather penny loafers"),
    ("tan-desert-boots", "pair of sand-tan suede desert boots with crepe soles"),
    ("brown-leather-messenger", "brown leather messenger bag with flap and shoulder strap"),
    ("silver-steel-watch", "silver stainless steel wristwatch with white dial and steel bracelet"),
    ("brown-leather-belt", "brown leather belt with brushed silver buckle"),
    ("tortoiseshell-sunglasses", "tortoiseshell acetate wayfarer sunglasses"),
]

PHOTO_PROMPT = (
    "Professional e-commerce product photograph of a single {desc}. The whole item is fully visible and "
    "centred, neatly presented flat-lay or on an invisible mannequin, soft natural studio light, plain off-white "
    "background, gentle shadow. Only this one item — no person, no other clothing, no props, no text, no logos."
)


def backend_env() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (ROOT / "backend" / ".env").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def psql(sql: str) -> str:
    return subprocess.check_output(
        ["docker", "exec", "-i", DB_CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-Atq", "-v", "ON_ERROR_STOP=1"],
        input=sql,
        text=True,
    ).strip()


def admin_headers(env: dict[str, str]) -> dict[str, str]:
    return {
        "apikey": env["SECRET_KEY"],
        "Authorization": f"Bearer {env['SERVICE_ROLE_KEY']}",
        "Content-Type": "application/json",
    }


def user_id_for(email: str) -> uuid.UUID:
    out = psql(f"select id from auth.users where lower(email) = lower('{email.replace(chr(39), '')}');")
    if not out:
        raise SystemExit(f"No local user with email {email}")
    return uuid.UUID(out.splitlines()[0])


def session_for(env: dict[str, str], email: str) -> str:
    link = smoke.request(
        "POST",
        f"{env['API_URL']}/auth/v1/admin/generate_link",
        headers=admin_headers(env),
        body={"type": "magiclink", "email": email},
    )
    hashed = link.get("hashed_token") or (link.get("properties") or {}).get("hashed_token")
    if not hashed:
        raise SystemExit("generate_link returned no hashed_token")
    public = {"apikey": env.get("PUBLISHABLE_KEY") or env["ANON_KEY"], "Content-Type": "application/json"}
    session = smoke.request(
        "POST", f"{env['API_URL']}/auth/v1/verify", headers=public, body={"type": "magiclink", "token_hash": hashed}
    )
    return str(session["access_token"])


def reset_wardrobe(env: dict[str, str], user_id: uuid.UUID) -> None:
    uid = str(user_id)
    keys = psql(
        f"""
        select object_key from public.wardrobe_media where user_id = '{uid}'
        union select image_object_key from public.garments where user_id = '{uid}'
        union select object_key from public.outfit_renders where user_id = '{uid}' and object_key is not null;
        """
    ).splitlines()
    keys = [k for k in keys if k]
    for start in range(0, len(keys), 100):
        smoke.request(
            "DELETE",
            f"{env['API_URL']}/storage/v1/object/wardrobe",
            headers=admin_headers(env),
            body={"prefixes": keys[start : start + 100]},
        )
    psql(
        f"""
        begin;
        delete from public.saved_looks where user_id = '{uid}';
        delete from public.outfits where user_id = '{uid}';
        delete from public.garments where user_id = '{uid}';
        delete from public.generation_jobs where user_id = '{uid}';
        delete from public.wardrobe_media where user_id = '{uid}';
        commit;
        """
    )
    print(f"Reset wardrobe: removed {len(keys)} stored object(s), garments, looks, renders, and jobs")


def generate_photo(cfg: dict[str, str], slug: str, desc: str) -> Path:
    path = CACHE / f"{slug}.jpg"
    if path.exists():
        return path
    body = {
        "model": cfg.get("GRYMODE_AI_IMAGE_MODEL", "gpt-image-2.5-sunburst"),
        "prompt": PHOTO_PROMPT.format(desc=desc),
        "size": "1024x1024",
        "quality": "medium",
        "output_format": "jpeg",
        "output_compression": 88,
        "n": 1,
    }
    base = cfg.get("GRYMODE_AI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    headers = {"Authorization": f"Bearer {cfg['GRYMODE_AI_API_KEY']}", "Content-Type": "application/json"}
    for attempt in range(3):
        try:
            payload = smoke.request("POST", f"{base}/images/generations", headers=headers, body=body, timeout=300)
            path.write_bytes(base64.b64decode(payload["data"][0]["b64_json"]))
            return path
        except SystemExit as exc:
            if attempt == 2:
                raise
            print(f"  retrying {slug}: {str(exc)[:160]}")
            time.sleep(5 * (attempt + 1))
    raise SystemExit(f"Could not generate {slug}")


def build_catalogue(cfg: dict[str, str]) -> list[Path]:
    CACHE.mkdir(parents=True, exist_ok=True)
    missing = [slug for slug, _ in CATALOGUE if not (CACHE / f"{slug}.jpg").exists()]
    if missing:
        print(f"Generating {len(missing)} product photo(s) with the image model (cached for reuse)…")
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=6) as pool:
        paths = list(pool.map(lambda item: generate_photo(cfg, *item), CATALOGUE))
    if missing:
        print(f"Product photos ready in {time.monotonic() - started:.0f}s")
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--email", required=True)
    parser.add_argument("--skip-reset", action="store_true")
    parser.add_argument("--no-wait-renders", action="store_true")
    parser.add_argument(
        "--rerender-only", action="store_true", help="keep the wardrobe and looks; (re)request every styled visual"
    )
    args = parser.parse_args()

    env = smoke.supabase_env()
    cfg = backend_env()
    if not cfg.get("GRYMODE_AI_API_KEY") or "REPLACE" in cfg["GRYMODE_AI_API_KEY"]:
        raise SystemExit("backend/.env needs GRYMODE_AI_API_KEY")

    user_id = user_id_for(args.email)
    print(f"Account {args.email} ({user_id})")
    if args.rerender_only:
        token = session_for(env, args.email)
        api = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        library = smoke.request("GET", f"{smoke.API_BASE}/v1/outfits", headers=api)
        unlocked = [look for look in library["outfits"] if not look["is_locked"]]
        for look in unlocked:
            smoke.request("POST", f"{smoke.API_BASE}/v1/outfits/{look['id']}/visual", headers=api)
        print(f"Requested styled visuals for {len(unlocked)} look(s)")
        return 0 if args.no_wait_renders else wait_for_visuals(api)
    if not args.skip_reset:
        reset_wardrobe(env, user_id)

    photos = build_catalogue(cfg)
    token = session_for(env, args.email)
    api = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=6) as pool:
        media_ids = set(pool.map(lambda p: smoke.upload(api, p), photos))
    print(f"Uploaded {len(media_ids)} photos; waiting for AI extraction…")
    summary = smoke.wait_for_extraction(api, media_ids, timeout_s=600)
    print(f"Extraction finished in {time.monotonic() - started:.0f}s")

    to_confirm: list[str] = []
    for garment in summary["garments"]:
        if garment["media_id"] and uuid.UUID(garment["media_id"]) in media_ids:
            print(f"  • {smoke.describe(garment)}")
            if garment.get("category"):
                to_confirm.append(garment["id"])
    failed = [j for j in summary["jobs"] if j["media_id"] and uuid.UUID(j["media_id"]) in media_ids and j["error_code"]]
    if failed:
        print(f"  {len(failed)} photo(s) had extraction notes: {sorted({j['error_code'] for j in failed})}")
    confirmed = smoke.request("POST", f"{smoke.API_BASE}/v1/wardrobe/confirm", headers=api, body={"garment_ids": to_confirm})
    print(f"Confirmed {confirmed['confirmed_count']} piece(s)")

    started = time.monotonic()
    start = smoke.request("POST", f"{smoke.API_BASE}/v1/outfits/generate", headers=api)
    job = start["job"]
    print("Generating looks with the outfit model…")
    while job["status"] in ("pending", "running"):
        time.sleep(3)
        job = smoke.request("GET", f"{smoke.API_BASE}/v1/outfits/jobs/{job['id']}", headers=api)
        if time.monotonic() - started > 900:
            raise SystemExit("Timed out waiting for generation")
    print(f"Generation {job['status']} in {time.monotonic() - started:.0f}s (error={job['error_code']})")
    if job["status"] != "succeeded":
        return 1

    library = smoke.request("GET", f"{smoke.API_BASE}/v1/outfits", headers=api)
    print(f"{library['accepted_count']} looks ({library['locked_count']} locked):")
    for look in library["outfits"]:
        pieces = ", ".join(
            f"{g.get('primary_color') or ''} {g.get('subcategory') or g['category']}".strip() for g in look["garments"]
        )
        print(f"  • {look['title']} [{', '.join(look['occasion_tags'])}] — {pieces}")

    if args.no_wait_renders:
        return 0
    return wait_for_visuals(api)


def wait_for_visuals(api: dict[str, str]) -> int:
    print("Rendering styled look visuals (high quality, ~1 min each, 3 at a time)…")
    started = time.monotonic()
    while True:
        library = smoke.request("GET", f"{smoke.API_BASE}/v1/outfits", headers=api)
        visuals = [look.get("visual") for look in library["outfits"] if not look["is_locked"]]
        done = [v for v in visuals if v and v["status"] in ("succeeded", "failed")]
        ok = [v for v in done if v["status"] == "succeeded"]
        print(f"  {len(ok)} ready, {len(done) - len(ok)} failed, {len(visuals) - len(done)} rendering")
        if len(done) == len(visuals):
            break
        if time.monotonic() - started > 1800:
            print("  still rendering after 30 min; the app will pick them up as they finish")
            break
        time.sleep(20)
    print(json.dumps({"looks": len(visuals), "visuals_ready": len(ok)}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
