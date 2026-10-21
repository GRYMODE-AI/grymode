"""Persistence helpers for outfit generation jobs and the outfit library."""

from __future__ import annotations

import hashlib
import uuid
from typing import Any

from app.db import DBConnection
from app.errors import APIError, ErrorCode
from app.outfit_models import OutfitSlot
from app.wardrobe import not_found

MIN_CONFIRMED_GARMENTS = 2
MAX_ACCEPTED_OUTFITS = 16


def wardrobe_fingerprint(garment_ids: list[uuid.UUID]) -> str:
    joined = ",".join(sorted(str(g) for g in garment_ids))
    return hashlib.sha256(joined.encode()).hexdigest()[:32]


async def list_confirmed_garments(connection: DBConnection, user_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await connection.fetch(
        """
        select id, category, subcategory, primary_color, secondary_colors, pattern, material,
               silhouette, formality, season_tags, style_tags, image_object_key
          from public.garments
         where user_id = $1
           and user_confirmed = true
           and category <> 'uncategorised'
         order by created_at asc
        """,
        user_id,
    )
    return [dict(row) for row in rows]


async def find_active_outfit_job(connection: DBConnection, user_id: uuid.UUID) -> dict[str, Any] | None:
    row = await connection.fetchrow(
        """
        select id, status, progress_stage, error_code, created_at, completed_at, idempotency_key
          from public.generation_jobs
         where user_id = $1 and job_type = 'outfit_generation'
           and status in ('pending', 'running')
         order by created_at desc
         limit 1
        """,
        user_id,
    )
    return dict(row) if row else None


async def find_job_by_idempotency(
    connection: DBConnection, user_id: uuid.UUID, idempotency_key: str
) -> dict[str, Any] | None:
    row = await connection.fetchrow(
        """
        select id, status, progress_stage, error_code, created_at, completed_at, idempotency_key
          from public.generation_jobs
         where user_id = $1 and idempotency_key = $2
        """,
        user_id,
        idempotency_key,
    )
    return dict(row) if row else None


async def create_outfit_job(connection: DBConnection, user_id: uuid.UUID, idempotency_key: str) -> dict[str, Any]:
    row = await connection.fetchrow(
        """
        insert into public.generation_jobs
            (user_id, media_id, job_type, status, progress_stage, idempotency_key)
        values ($1, null, 'outfit_generation', 'pending', 'queued', $2)
        on conflict (user_id, idempotency_key) do update
           set status = case
                   when generation_jobs.status = 'failed' then 'pending'
                   else generation_jobs.status
               end,
               progress_stage = case
                   when generation_jobs.status = 'failed' then 'queued'
                   else generation_jobs.progress_stage
               end,
               error_code = case
                   when generation_jobs.status = 'failed' then null
                   else generation_jobs.error_code
               end,
               completed_at = case
                   when generation_jobs.status = 'failed' then null
                   else generation_jobs.completed_at
               end
        returning id, status, progress_stage, error_code, created_at, completed_at, idempotency_key
        """,
        user_id,
        idempotency_key,
    )
    if row is None:
        raise APIError(
            503,
            ErrorCode.SERVICE_UNAVAILABLE,
            "We couldn't start outfit generation. Please try again.",
            retryable=True,
        )
    return dict(row)


async def fetch_outfit_job(connection: DBConnection, user_id: uuid.UUID, job_id: uuid.UUID) -> dict[str, Any]:
    row = await connection.fetchrow(
        """
        select id, status, progress_stage, error_code, created_at, completed_at, idempotency_key
          from public.generation_jobs
         where id = $1 and user_id = $2 and job_type = 'outfit_generation'
        """,
        job_id,
        user_id,
    )
    if row is None:
        raise not_found("generation job")
    return dict(row)


async def count_accepted_outfits(connection: DBConnection, user_id: uuid.UUID) -> int:
    return int(
        await connection.fetchval(
            "select count(*)::int from public.outfits where user_id = $1",
            user_id,
        )
        or 0
    )


async def claim_outfit_job(connection: DBConnection, job_id: uuid.UUID, user_id: uuid.UUID) -> dict[str, Any] | None:
    row = await connection.fetchrow(
        """
        update public.generation_jobs
           set status = 'running',
               started_at = coalesce(started_at, now()),
               attempt_count = attempt_count + 1,
               progress_stage = 'composing'
         where id = $1 and user_id = $2 and job_type = 'outfit_generation'
           and status in ('pending', 'failed')
           and attempt_count < 5
        returning id, status, attempt_count
        """,
        job_id,
        user_id,
    )
    return dict(row) if row else None


async def mark_outfit_job_progress(connection: DBConnection, job_id: uuid.UUID, stage: str) -> None:
    await connection.execute(
        "update public.generation_jobs set progress_stage = $2 where id = $1",
        job_id,
        stage,
    )


async def succeed_outfit_job(connection: DBConnection, job_id: uuid.UUID) -> None:
    await connection.execute(
        """
        update public.generation_jobs
           set status = 'succeeded',
               progress_stage = 'ready',
               completed_at = now(),
               error_code = null
         where id = $1
        """,
        job_id,
    )


async def fail_outfit_job(connection: DBConnection, job_id: uuid.UUID, error_code: str) -> None:
    await connection.execute(
        """
        update public.generation_jobs
           set status = 'failed',
               progress_stage = 'failed',
               completed_at = now(),
               error_code = $2
         where id = $1
        """,
        job_id,
        error_code,
    )


async def replace_outfits_for_job(
    connection: DBConnection,
    *,
    user_id: uuid.UUID,
    job_id: uuid.UUID,
    outfits: list[dict[str, Any]],
) -> int:
    """Upsert the library by garment-set signature so paid renders survive a refresh.

    Matching signatures keep the same outfit UUID (and therefore ``outfit_renders`` rows).
    Signatures absent from the new batch are deleted (cascade drops obsolete renders only).
    """
    existing_rows = await connection.fetch("select id, signature from public.outfits where user_id = $1", user_id)
    by_signature = {str(row["signature"]): row["id"] for row in existing_rows}
    incoming = {str(outfit["signature"]) for outfit in outfits}

    obsolete = [row["id"] for row in existing_rows if str(row["signature"]) not in incoming]
    if obsolete:
        await connection.execute("delete from public.outfits where id = any($1::uuid[])", obsolete)

    await connection.execute("update public.outfits set is_free_reveal = false where user_id = $1", user_id)

    accepted = 0
    for index, outfit in enumerate(outfits):
        signature = str(outfit["signature"])
        existing_id = by_signature.get(signature)
        if existing_id is not None:
            await connection.execute(
                """
                update public.outfits
                   set title = $2,
                       occasion_tags = $3,
                       style_tags = $4,
                       contextual_tags = $5,
                       score = $6,
                       is_free_reveal = $7,
                       generation_job_id = $8
                 where id = $1
                """,
                existing_id,
                outfit["title"],
                outfit["occasion_tags"],
                outfit["style_tags"],
                outfit["contextual_tags"],
                outfit["score"],
                index == 0,
                job_id,
            )
            await connection.execute("delete from public.outfit_garments where outfit_id = $1", existing_id)
            outfit_id = existing_id
        else:
            outfit_id = await connection.fetchval(
                """
                insert into public.outfits
                    (user_id, title, signature, occasion_tags, style_tags, contextual_tags,
                     score, is_free_reveal, generation_job_id)
                values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                returning id
                """,
                user_id,
                outfit["title"],
                signature,
                outfit["occasion_tags"],
                outfit["style_tags"],
                outfit["contextual_tags"],
                outfit["score"],
                index == 0,
                job_id,
            )
        for piece in outfit["garments"]:
            await connection.execute(
                """
                insert into public.outfit_garments (outfit_id, garment_id, slot, position)
                values ($1, $2, $3, $4)
                """,
                outfit_id,
                piece["garment_id"],
                piece["slot"] if isinstance(piece["slot"], str) else piece["slot"].value,
                piece["position"],
            )
        accepted += 1
    return accepted


async def list_outfits(connection: DBConnection, user_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await connection.fetch(
        """
        select id, title, signature, occasion_tags, style_tags, contextual_tags,
               score, is_free_reveal, created_at
          from public.outfits
         where user_id = $1
         order by is_free_reveal desc, score desc, created_at desc
        """,
        user_id,
    )
    return [dict(row) for row in rows]


async def fetch_outfit(connection: DBConnection, user_id: uuid.UUID, outfit_id: uuid.UUID) -> dict[str, Any]:
    row = await connection.fetchrow(
        """
        select id, title, signature, occasion_tags, style_tags, contextual_tags,
               score, is_free_reveal, created_at
          from public.outfits
         where id = $1 and user_id = $2
        """,
        outfit_id,
        user_id,
    )
    if row is None:
        raise not_found("look")
    return dict(row)


async def list_saved_outfit_ids(connection: DBConnection, user_id: uuid.UUID) -> set[uuid.UUID]:
    rows = await connection.fetch(
        """
        select outfit_id
          from public.saved_looks
         where user_id = $1
        """,
        user_id,
    )
    return {row["outfit_id"] for row in rows}


async def count_saved_looks(connection: DBConnection, user_id: uuid.UUID) -> int:
    value = await connection.fetchval(
        "select count(*)::int from public.saved_looks where user_id = $1",
        user_id,
    )
    return int(value or 0)


async def save_look(connection: DBConnection, user_id: uuid.UUID, outfit_id: uuid.UUID) -> None:
    await connection.execute(
        """
        insert into public.saved_looks (user_id, outfit_id)
        values ($1, $2)
        on conflict (user_id, outfit_id) do nothing
        """,
        user_id,
        outfit_id,
    )


async def unsave_look(connection: DBConnection, user_id: uuid.UUID, outfit_id: uuid.UUID) -> None:
    result = await connection.execute(
        """
        delete from public.saved_looks
         where user_id = $1 and outfit_id = $2
        """,
        user_id,
        outfit_id,
    )
    if result == "DELETE 0":
        raise not_found("saved look")


async def count_confirmed_garments(connection: DBConnection, user_id: uuid.UUID) -> int:
    value = await connection.fetchval(
        """
        select count(*)::int
          from public.garments
         where user_id = $1
           and user_confirmed = true
           and category <> 'uncategorised'
        """,
        user_id,
    )
    return int(value or 0)


def pick_todays_look(
    rows: list[dict[str, Any]],
    *,
    user_id: uuid.UUID,
    day_key: str,
    plan: str,
) -> dict[str, Any] | None:
    """Deterministic daily pick: free reveal for free users; rotate among all for premium."""
    if not rows:
        return None
    if plan != "premium":
        for row in rows:
            if row.get("is_free_reveal"):
                return row
        return rows[0]
    digest = hashlib.sha256(f"{user_id}:{day_key}".encode()).hexdigest()
    index = int(digest[:8], 16) % len(rows)
    return rows[index]


def occasion_filter_values(rows: list[dict[str, Any]]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for row in rows:
        for tag in row.get("occasion_tags") or []:
            if tag and tag not in seen:
                seen.add(tag)
                ordered.append(tag)
    return ordered


async def list_outfit_garments(
    connection: DBConnection, user_id: uuid.UUID, outfit_ids: list[uuid.UUID]
) -> list[dict[str, Any]]:
    if not outfit_ids:
        return []
    rows = await connection.fetch(
        """
        select og.outfit_id, og.garment_id, og.slot, og.position,
               g.category, g.subcategory, g.primary_color, g.secondary_colors, g.pattern,
               g.material, g.image_object_key
          from public.outfit_garments og
          join public.garments g on g.id = og.garment_id
          join public.outfits o on o.id = og.outfit_id
         where o.user_id = $1 and og.outfit_id = any($2::uuid[])
         order by og.outfit_id, og.position
        """,
        user_id,
        outfit_ids,
    )
    return [dict(row) for row in rows]


async def latest_outfit_job(connection: DBConnection, user_id: uuid.UUID) -> dict[str, Any] | None:
    row = await connection.fetchrow(
        """
        select id, status, progress_stage, error_code, created_at, completed_at, idempotency_key
          from public.generation_jobs
         where user_id = $1 and job_type = 'outfit_generation'
         order by created_at desc
         limit 1
        """,
        user_id,
    )
    return dict(row) if row else None


def slot_enum(value: str) -> OutfitSlot:
    return OutfitSlot(value)
