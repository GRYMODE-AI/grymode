#!/usr/bin/env python3
"""Seed the App Review demo user with a deterministic wardrobe and outfit library.

Local Supabase only. Idempotent: clears prior demo wardrobe/looks for the user, then reseeds.
"""

from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEMO_EMAIL = os.environ.get("GRYMODE_DEMO_EMAIL", "review@grymode.test")
DEMO_PASSWORD = os.environ.get("GRYMODE_DEMO_PASSWORD", "GrymodeReview!2026")

GARMENTS = [
    # media_id, garment_id, category, color, slot_hint, rgb
    ("11111111-1111-4111-8111-111111111101", "21111111-1111-4111-8111-111111111101", "tops", "navy", (32, 48, 80)),
    ("11111111-1111-4111-8111-111111111102", "21111111-1111-4111-8111-111111111102", "bottoms", "charcoal", (48, 48, 52)),
    ("11111111-1111-4111-8111-111111111103", "21111111-1111-4111-8111-111111111103", "shoes", "black", (24, 24, 24)),
    ("11111111-1111-4111-8111-111111111104", "21111111-1111-4111-8111-111111111104", "outerwear", "olive", (72, 80, 48)),
    ("11111111-1111-4111-8111-111111111105", "21111111-1111-4111-8111-111111111105", "tops", "cream", (232, 224, 208)),
    ("11111111-1111-4111-8111-111111111106", "21111111-1111-4111-8111-111111111106", "bottoms", "sand", (180, 160, 120)),
    ("11111111-1111-4111-8111-111111111107", "21111111-1111-4111-8111-111111111107", "shoes", "brown", (96, 64, 40)),
    ("11111111-1111-4111-8111-111111111108", "21111111-1111-4111-8111-111111111108", "knitwear", "grey", (140, 140, 144)),
]

# Each look: title, signature, occasions, styles, garment indices, free?
LOOKS = [
    ("Atelier navy · Work", "demo-look-01", ["Work"], ["Classic"], [0, 1, 2], True, 0.92),
    ("Olive layer · Weekend", "demo-look-02", ["Weekend"], ["Relaxed"], [4, 5, 6, 3], False, 0.88),
    ("Knit commute", "demo-look-03", ["Work", "Travel"], ["Contemporary"], [7, 1, 2], False, 0.84),
    ("Cream weekend", "demo-look-04", ["Weekend"], ["Relaxed"], [4, 5, 6], False, 0.80),
    ("Navy evening", "demo-look-05", ["Evenings out"], ["Classic"], [0, 1, 2, 3], False, 0.76),
    ("Travel easy", "demo-look-06", ["Travel"], ["Relaxed"], [7, 5, 6], False, 0.72),
    ("Studio charcoal", "demo-look-07", ["Work"], ["Contemporary"], [0, 1, 6], False, 0.68),
    ("Sand day", "demo-look-08", ["Weekend"], ["Relaxed"], [4, 5, 2], False, 0.64),
    ("Layered olive", "demo-look-09", ["Travel", "Weekend"], ["Classic"], [7, 1, 2, 3], False, 0.60),
]

SLOT_FOR_CATEGORY = {
    "tops": "primary",
    "knitwear": "primary",
    "bottoms": "bottom",
    "shoes": "footwear",
    "outerwear": "outerwear",
}


def supabase_env() -> dict[str, str]:
    out = subprocess.check_output(["supabase", "status", "-o", "env"], cwd=ROOT, text=True)
    env: dict[str, str] = {}
    for line in out.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key] = value.strip().strip('"')
    return env


def png_bytes(rgb: tuple[int, int, int], width: int = 240, height: int = 320) -> bytes:
    r, g, b = rgb
    raw = b"".join(b"\x00" + bytes([r, g, b]) * width for _ in range(height))
    compressed = zlib.compress(raw, 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")


def http_json(method: str, url: str, headers: dict[str, str], body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = resp.read().decode()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        raise RuntimeError(f"{method} {url} -> {exc.code}: {detail}") from exc


def ensure_user(api_url: str, secret: str) -> uuid.UUID:
    headers = {
        "apikey": secret,
        "Authorization": f"Bearer {secret}",
        "Content-Type": "application/json",
    }
    # List by email
    listed = http_json(
        "GET",
        f"{api_url}/auth/v1/admin/users?page=1&per_page=200",
        headers,
    )
    for user in listed.get("users", []):
        if (user.get("email") or "").lower() == DEMO_EMAIL.lower():
            return uuid.UUID(user["id"])

    created = http_json(
        "POST",
        f"{api_url}/auth/v1/admin/users",
        headers,
        {
            "email": DEMO_EMAIL,
            "password": DEMO_PASSWORD,
            "email_confirm": True,
            "user_metadata": {"demo": True, "role": "app_review"},
        },
    )
    return uuid.UUID(created["id"])


def upload_object(api_url: str, secret: str, object_key: str, data: bytes, content_type: str) -> None:
    headers = {
        "apikey": secret,
        "Authorization": f"Bearer {secret}",
        "Content-Type": content_type,
        "x-upsert": "true",
    }
    url = f"{api_url}/storage/v1/object/wardrobe/{object_key}"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
    except urllib.error.HTTPError as exc:
        # Some stacks prefer PUT for upsert.
        if exc.code in {400, 409}:
            req = urllib.request.Request(url, data=data, headers=headers, method="PUT")
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp.read()
            return
        raise RuntimeError(f"upload {object_key} -> {exc.code}: {exc.read().decode()}") from exc


def psql(sql: str) -> None:
    subprocess.run(
        ["docker", "exec", "-i", "supabase_db_grymode", "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
        input=sql.encode(),
        cwd=ROOT,
        check=True,
    )


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def pg_text_array(values: list[str]) -> str:
    parts = []
    for value in values:
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        parts.append(f'"{escaped}"')
    return "'{" + ",".join(parts) + "}'"


def seed(user_id: uuid.UUID, api_url: str, secret: str) -> None:
    job_id = uuid.UUID("31111111-1111-4111-8111-111111111111")

    # Clear prior demo rows (cascades outfits via garments restrict — delete outfits first).
    psql(
        f"""
        delete from public.outfit_garments where outfit_id in (select id from public.outfits where user_id = '{user_id}');
        delete from public.outfits where user_id = '{user_id}';
        delete from public.garments where user_id = '{user_id}';
        delete from public.generation_jobs where user_id = '{user_id}';
        delete from public.wardrobe_media where user_id = '{user_id}';
        """
    )

    statements: list[str] = []
    statements.append(
        f"""
        insert into public.profiles (id, display_name, style_profile, onboarding_completed_at)
        values (
          '{user_id}',
          'App Review',
          '{{"axes":{{"silhouette":"first","character":"second","finish":"first"}},"occasions":["work","weekend"],"palettes":["neutrals","earthTones"]}}'::jsonb,
          now()
        )
        on conflict (id) do update set
          display_name = excluded.display_name,
          style_profile = excluded.style_profile,
          onboarding_completed_at = coalesce(public.profiles.onboarding_completed_at, excluded.onboarding_completed_at);
        """
    )
    statements.append(
        f"""
        insert into public.entitlements (user_id, plan, source, expires_at)
        values ('{user_id}', 'premium', 'demo_seed', now() + interval '365 days')
        on conflict (user_id) do update set plan = 'premium', source = 'demo_seed', expires_at = excluded.expires_at;
        """
    )
    statements.append(
        f"""
        insert into public.generation_jobs
          (id, user_id, media_id, job_type, status, progress_stage, idempotency_key, completed_at)
        values (
          '{job_id}', '{user_id}', null, 'outfit_generation', 'succeeded', 'persisting',
          'demo-seed-outfit-gen', now()
        );
        """
    )

    for media_id, garment_id, category, color, rgb in GARMENTS:
        media_uuid = uuid.UUID(media_id)
        garment_uuid = uuid.UUID(garment_id)
        object_key = f"{user_id}/{media_uuid}/original.png"
        upload_object(api_url, secret, object_key, png_bytes(rgb), "image/png")
        statements.append(
            f"""
            insert into public.wardrobe_media
              (id, user_id, object_key, media_type, content_type, processing_status, byte_size)
            values (
              '{media_uuid}', '{user_id}', {sql_quote(object_key)}, 'photo', 'image/png', 'ready', 4096
            );
            """
        )
        statements.append(
            f"""
            insert into public.garments
              (id, user_id, media_id, category, primary_color, formality, season_tags, style_tags,
               image_object_key, confidence, user_confirmed)
            values (
              '{garment_uuid}', '{user_id}', '{media_uuid}', '{category}', {sql_quote(color)},
              'smartCasual', {pg_text_array(["allSeason"])}, {pg_text_array(["demo"])},
              {sql_quote(object_key)}, 0.95, true
            );
            """
        )

    for title, signature, occasions, styles, indices, is_free, score in LOOKS:
        outfit_id = uuid.uuid5(uuid.NAMESPACE_URL, f"grymode-demo:{signature}")
        statements.append(
            f"""
            insert into public.outfits
              (id, user_id, title, signature, occasion_tags, style_tags, contextual_tags,
               score, is_free_reveal, generation_job_id)
            values (
              '{outfit_id}', '{user_id}', {sql_quote(title)}, {sql_quote(signature)},
              {pg_text_array(occasions)}, {pg_text_array(styles)}, {pg_text_array(["Daytime"])},
              {score}, {'true' if is_free else 'false'}, '{job_id}'
            );
            """
        )
        for position, gi in enumerate(indices):
            _media, garment_id, category, _color, _rgb = GARMENTS[gi]
            slot = SLOT_FOR_CATEGORY[category]
            # Prefer outerwear slot when category is outerwear even if also primary-capable.
            statements.append(
                f"""
                insert into public.outfit_garments (outfit_id, garment_id, slot, position)
                values ('{outfit_id}', '{garment_id}', '{slot}', {position});
                """
            )

    # Height / build for try-on path (no face photo in automated seed).
    statements.append(
        f"""
        insert into public.avatar_profiles (user_id, height_cm, body_build)
        values ('{user_id}', 178, 'regular')
        on conflict (user_id) do update set height_cm = 178, body_build = 'regular';
        """
    )

    psql("\n".join(statements))


def main() -> int:
    env = supabase_env()
    api_url = env["API_URL"]
    secret = env.get("SECRET_KEY") or env["SERVICE_ROLE_KEY"]
    user_id = ensure_user(api_url, secret)
    print(f"demo_user={user_id} email={DEMO_EMAIL}")
    seed(user_id, api_url, secret)
    print("seeded: 8 garments, 9 looks, premium entitlement, avatar measurements")
    print("sign-in: email OTP via Mailpit, or password if Auth password grant is enabled")
    print(f"password (admin-set): {DEMO_PASSWORD}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 — CLI surface
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
