#!/usr/bin/env python3
"""End-to-end check of the real AI pipeline through the local Grymode API.

Signs in as a local user, uploads clothing photos exactly like the iOS app, waits for
extraction, and (optionally) confirms the proposed pieces and generates looks.

Local stack only. Usage:
    scripts/ai-smoke-test.py photo1.jpg [photo2.jpg ...] [--confirm] [--generate]
    scripts/ai-smoke-test.py --generate            # regenerate looks from the confirmed wardrobe
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
API_BASE = os.environ.get("GRYMODE_API_BASE", "http://127.0.0.1:8000")


def supabase_env() -> dict[str, str]:
    out = subprocess.check_output(["supabase", "status", "-o", "env"], cwd=ROOT, text=True)
    env: dict[str, str] = {}
    for line in out.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            env[key] = value.strip().strip('"')
    return env


def request(
    method: str, url: str, *, headers: dict[str, str], body: Any = None, raw: bytes | None = None, timeout: int = 60
) -> Any:
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = resp.read().decode()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"{method} {url} -> {exc.code}: {exc.read().decode()[:400]}") from exc


def sign_in(env: dict[str, str], email: str, password: str) -> str:
    key = env.get("PUBLISHABLE_KEY") or env["ANON_KEY"]
    payload = request(
        "POST",
        f"{env['API_URL']}/auth/v1/token?grant_type=password",
        headers={"apikey": key, "Content-Type": "application/json"},
        body={"email": email, "password": password},
    )
    return str(payload["access_token"])


def describe(garment: dict[str, Any]) -> str:
    parts = [garment.get("primary_color"), garment.get("subcategory") or garment["category"]]
    extra = [garment.get("material"), garment.get("pattern"), garment.get("formality")]
    confidence = garment.get("confidence")
    tail = ", ".join(str(x) for x in extra if x)
    conf = f" (confidence {confidence:.2f})" if isinstance(confidence, (int, float)) else ""
    return f"[{garment['category']}] {' '.join(str(p) for p in parts if p)}{' — ' + tail if tail else ''}{conf}"


def upload(api: dict[str, str], path: Path) -> uuid.UUID:
    data = path.read_bytes()
    content_type = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    slot = request(
        "POST",
        f"{API_BASE}/v1/wardrobe/uploads",
        headers=api,
        body={
            "media_type": "photo",
            "content_type": content_type,
            "byte_size": len(data),
            "client_upload_id": str(uuid.uuid4()),
        },
    )
    request(
        "PUT",
        slot["upload_url"],
        headers={"Content-Type": content_type, "x-upsert": "true"},
        raw=data,
    )
    request("POST", f"{API_BASE}/v1/wardrobe/uploads/{slot['media_id']}/complete", headers=api)
    return uuid.UUID(slot["media_id"])


def wait_for_extraction(api: dict[str, str], media_ids: set[uuid.UUID], timeout_s: int = 180) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_s
    while True:
        summary = request("GET", f"{API_BASE}/v1/wardrobe", headers=api)
        jobs = [j for j in summary["jobs"] if j["media_id"] and uuid.UUID(j["media_id"]) in media_ids]
        if jobs and all(j["status"] in ("succeeded", "failed") for j in jobs):
            return summary
        if time.monotonic() > deadline:
            raise SystemExit("Timed out waiting for extraction")
        time.sleep(2)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photos", nargs="*", type=Path)
    parser.add_argument("--email", default=os.environ.get("GRYMODE_DEMO_EMAIL", "review@grymode.test"))
    parser.add_argument("--password", default=os.environ.get("GRYMODE_DEMO_PASSWORD", "GrymodeReview!2026"))
    parser.add_argument("--confirm", action="store_true", help="confirm the newly proposed pieces")
    parser.add_argument("--generate", action="store_true", help="generate looks from the confirmed wardrobe")
    args = parser.parse_args()
    if not args.photos and not args.generate:
        parser.error("pass at least one photo or --generate")

    env = supabase_env()
    token = sign_in(env, args.email, args.password)
    api = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    print(f"Signed in as {args.email}")

    new_garment_ids: list[str] = []
    if args.photos:
        started = time.monotonic()
        media_ids = {upload(api, path) for path in args.photos}
        print(f"Uploaded {len(media_ids)} photo(s); waiting for AI extraction…")
        summary = wait_for_extraction(api, media_ids)
        print(f"Extraction finished in {time.monotonic() - started:.1f}s")
        for job in summary["jobs"]:
            if job["media_id"] and uuid.UUID(job["media_id"]) in media_ids:
                note = f" note={job['error_code']}" if job["error_code"] else ""
                print(f"  job {job['status']}{note}")
        for garment in summary["garments"]:
            if garment["media_id"] and uuid.UUID(garment["media_id"]) in media_ids:
                new_garment_ids.append(garment["id"])
                print(f"  • {describe(garment)}")

    if args.confirm and new_garment_ids:
        confirmed = request(
            "POST", f"{API_BASE}/v1/wardrobe/confirm", headers=api, body={"garment_ids": new_garment_ids}
        )
        print(f"Confirmed {confirmed['confirmed_count']} piece(s)")

    if args.generate:
        started = time.monotonic()
        start = request("POST", f"{API_BASE}/v1/outfits/generate", headers=api)
        job = start["job"]
        print(f"Generation job {job['status']} (reused={start['reused_existing']}); waiting…")
        while job["status"] in ("pending", "running"):
            time.sleep(3)
            job = request("GET", f"{API_BASE}/v1/outfits/jobs/{job['id']}", headers=api)
            if time.monotonic() - started > 600:
                raise SystemExit("Timed out waiting for generation")
        print(f"Generation {job['status']} in {time.monotonic() - started:.1f}s, error={job['error_code']}")
        library = request("GET", f"{API_BASE}/v1/outfits", headers=api)
        print(f"{library['accepted_count']} looks:")
        for look in library["outfits"]:
            pieces = ", ".join(f"{g['slot']}:{g.get('primary_color') or ''} {g['category']}" for g in look["garments"])
            print(f"  • {look['title']} [{', '.join(look['occasion_tags'])}] score={look['score']:.2f} — {pieces}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
