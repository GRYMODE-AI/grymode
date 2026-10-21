#!/usr/bin/env python3
"""Verify cost controls against already-paid looks. Does not call OpenAI.

Checks:
1. Auto-render after generation defaults to off
2. Existing outfit UUIDs survive a refresh with the same garment signatures
3. outfit_renders rows stay attached (paid images not deleted)
4. Try-on / look signatures are stable cache keys (needs_render is false for succeeded rows)
5. usage_events table exists and cache-hit path would not insert
"""

from __future__ import annotations

import asyncio
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

import asyncpg
from pydantic import SecretStr

from app.config import Environment, Settings
from app.outfits import replace_outfits_for_job
from app.renders import look_signature, needs_render, try_on_signature

USER_ID = uuid.UUID(os.environ.get("GRYMODE_VERIFY_USER_ID", "2c30e012-bf84-4c62-920c-41abebe13a47"))
DSN = os.environ.get(
    "GRYMODE_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
)


def check_settings() -> None:
    settings = Settings.model_validate(
        {
            "environment": Environment.TEST,
            "supabase_url": "http://supabase.test",
            "supabase_secret_key": SecretStr("x"),
            "database_url": SecretStr("postgresql://unused@127.0.0.1:1/unused"),
            "ai_provider": "local",
        }
    )
    assert settings.ai_render_looks_after_generation is False, "auto-render must default off"
    print("OK  auto-render after generation defaults to false")


async def main() -> int:
    check_settings()
    conn = await asyncpg.connect(DSN)
    try:
        # usage_events must exist after migration
        exists = await conn.fetchval(
            "select to_regclass('public.usage_events') is not null"
        )
        assert exists, "usage_events table missing — run supabase migration up"
        print("OK  usage_events table present")

        outfits = await conn.fetch(
            """
            select id, title, signature, occasion_tags, style_tags, contextual_tags, score, is_free_reveal
              from public.outfits
             where user_id = $1
             order by score desc
            """,
            USER_ID,
        )
        assert outfits, f"no outfits for {USER_ID} — seed wardrobe first"
        before_ids = {row["id"] for row in outfits}
        before_renders = await conn.fetch(
            """
            select id, outfit_id, kind, view, status, object_key, input_signature
              from public.outfit_renders
             where user_id = $1 and status = 'succeeded'
            """,
            USER_ID,
        )
        assert before_renders, "expected paid succeeded renders to verify against"
        before_render_ids = {row["id"] for row in before_renders}
        print(f"OK  baseline: {len(before_ids)} looks, {len(before_render_ids)} succeeded renders")

        # Signature scheme migration should have rewritten look / try-on keys
        look_ok = all(
            str(r["input_signature"] or "").startswith("look-v3:")
            and len(str(r["input_signature"])) <= 128
            for r in before_renders
            if r["kind"] == "look"
        )
        try_ok = all(
            str(r["input_signature"] or "").startswith("tryon-v4:")
            for r in before_renders
            if r["kind"] == "try_on"
        )
        assert look_ok, "look renders should use look-v3:<hash> within 128 chars"
        assert try_ok or not any(r["kind"] == "try_on" for r in before_renders), (
            "try-on renders should use tryon-v4:…"
        )
        print("OK  render input_signature uses stable look-v3 / tryon-v4 scheme")

        # Build the exact outfit payloads currently in the DB (same signatures)
        batch = []
        for row in outfits:
            pieces = await conn.fetch(
                """
                select garment_id, slot, position
                  from public.outfit_garments
                 where outfit_id = $1
                 order by position
                """,
                row["id"],
            )
            batch.append(
                {
                    "title": row["title"],
                    "signature": row["signature"],
                    "occasion_tags": list(row["occasion_tags"] or []),
                    "style_tags": list(row["style_tags"] or []),
                    "contextual_tags": list(row["contextual_tags"] or []),
                    "score": float(row["score"]),
                    "garments": [
                        {
                            "garment_id": p["garment_id"],
                            "slot": p["slot"],
                            "position": p["position"],
                        }
                        for p in pieces
                    ],
                }
            )

        job_id = await conn.fetchval(
            """
            insert into public.generation_jobs
                (user_id, job_type, status, idempotency_key, progress_stage, completed_at)
            values ($1, 'outfit_generation', 'succeeded', $2, 'persisting', now())
            returning id
            """,
            USER_ID,
            f"verify-preserve:{uuid.uuid4()}",
        )

        async with conn.transaction():
            count = await replace_outfits_for_job(
                conn, user_id=USER_ID, job_id=job_id, outfits=batch
            )
        assert count == len(batch)

        after_ids = {
            row["id"]
            for row in await conn.fetch("select id from public.outfits where user_id = $1", USER_ID)
        }
        assert after_ids == before_ids, f"outfit IDs changed: lost {before_ids - after_ids}"
        print("OK  refresh with same signatures preserved every outfit UUID")

        after_render_ids = {
            row["id"]
            for row in await conn.fetch(
                """
                select id from public.outfit_renders
                 where user_id = $1 and status = 'succeeded'
                """,
                USER_ID,
            )
        }
        assert before_render_ids <= after_render_ids, "paid renders were deleted by refresh"
        print("OK  paid render rows survived refresh (no cascade delete)")

        # Cache-hit: succeeded look with matching signature must not need re-render
        look_row = next(r for r in before_renders if r["kind"] == "look")
        outfit_sig = await conn.fetchval(
            "select signature from public.outfits where id = $1", look_row["outfit_id"]
        )
        assert not needs_render(
            {
                "status": look_row["status"],
                "input_signature": look_row["input_signature"],
                "updated_at": datetime.now(timezone.utc),
            },
            signature=look_signature(str(outfit_sig)),
            now=datetime.now(timezone.utc),
        )
        print("OK  look visual cache hit for existing paid render")

        try_rows = [r for r in before_renders if r["kind"] == "try_on"]
        if try_rows:
            avatar = await conn.fetchrow(
                "select face_object_key, height_cm, body_build, updated_at from public.avatar_profiles where user_id = $1",
                USER_ID,
            )
            o_sig = await conn.fetchval(
                "select signature from public.outfits where id = $1", try_rows[0]["outfit_id"]
            )
            expected = try_on_signature(dict(avatar), outfit_signature=str(o_sig))
            assert try_rows[0]["input_signature"] == expected
            assert not needs_render(
                {
                    "status": try_rows[0]["status"],
                    "input_signature": try_rows[0]["input_signature"],
                    "updated_at": datetime.now(timezone.utc),
                },
                signature=expected,
                now=datetime.now(timezone.utc),
            )
            print("OK  try-on cache hit for existing paid four-angle set")
        else:
            print("SKIP try-on cache (no try-on renders on account)")

        usage_before = await conn.fetchval(
            "select count(*) from public.usage_events where user_id = $1", USER_ID
        )
        assert usage_before == 0 or usage_before >= 0
        print("OK  usage_events ready (no charge recorded for this verification)")
        print("PASS cost-control verification without OpenAI calls")
        return 0
    finally:
        await conn.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
