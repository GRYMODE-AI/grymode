from __future__ import annotations

import uuid
from typing import Any

from app.auth import AuthenticatedUser
from app.db import DBConnection
from app.errors import APIError, ErrorCode
from app.wardrobe_models import (
    EXTENSION_FOR_CONTENT_TYPE,
    MAX_MEDIA_PER_USER,
    MAX_PENDING_UPLOADS,
    CreateUploadRequest,
    ExtractedGarment,
    Formality,
    GarmentCategory,
    JobStatus,
    MediaProcessingStatus,
    MediaType,
)


def not_found(kind: str = "item") -> APIError:
    return APIError(404, ErrorCode.NOT_FOUND, f"That wardrobe {kind} was not found.")


async def count_media(connection: DBConnection, user_id: uuid.UUID) -> int:
    value: int = await connection.fetchval(
        "select count(*)::int from public.wardrobe_media where user_id = $1 and retention_status = 'active'",
        user_id,
    )
    return value


async def count_awaiting_upload(connection: DBConnection, user_id: uuid.UUID) -> int:
    value: int = await connection.fetchval(
        """
        select count(*)::int from public.wardrobe_media
         where user_id = $1 and processing_status = 'awaiting_upload'
        """,
        user_id,
    )
    return value


async def create_upload_slot(
    connection: DBConnection, user: AuthenticatedUser, body: CreateUploadRequest
) -> tuple[uuid.UUID, str, uuid.UUID]:
    total = await count_media(connection, user.id)
    if total >= MAX_MEDIA_PER_USER:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            f"You can store up to {MAX_MEDIA_PER_USER} wardrobe uploads. Remove some pieces first.",
        )
    pending = await count_awaiting_upload(connection, user.id)
    if pending >= MAX_PENDING_UPLOADS:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            "Finish or cancel your current uploads before starting more.",
        )

    media_id = uuid.uuid4()
    ext = EXTENSION_FOR_CONTENT_TYPE[body.content_type]
    object_key = f"{user.id}/{media_id}/original.{ext}"
    idempotency_key = f"extract:{body.client_upload_id}"

    await connection.execute(
        """
        insert into public.wardrobe_media
            (id, user_id, object_key, media_type, content_type, byte_size, processing_status)
        values ($1, $2, $3, $4, $5, $6, 'awaiting_upload')
        """,
        media_id,
        user.id,
        object_key,
        body.media_type.value,
        body.content_type,
        body.byte_size,
    )
    job_id = await connection.fetchval(
        """
        insert into public.generation_jobs
            (user_id, media_id, job_type, status, progress_stage, idempotency_key)
        values ($1, $2, 'garment_extraction', 'pending', 'waiting_for_upload', $3)
        on conflict (user_id, idempotency_key)
        do update set media_id = excluded.media_id
        returning id
        """,
        user.id,
        media_id,
        idempotency_key,
    )
    if not isinstance(job_id, uuid.UUID):
        raise APIError(
            503,
            ErrorCode.SERVICE_UNAVAILABLE,
            "We couldn't start the upload. Please try again.",
            retryable=True,
        )
    return media_id, object_key, job_id


async def mark_uploaded(connection: DBConnection, user_id: uuid.UUID, media_id: uuid.UUID) -> uuid.UUID:
    row = await connection.fetchrow(
        """
        update public.wardrobe_media
           set processing_status = 'uploaded'
         where id = $1 and user_id = $2 and processing_status in ('awaiting_upload', 'uploaded')
        returning id
        """,
        media_id,
        user_id,
    )
    if row is None:
        raise not_found("upload")
    job_id = await connection.fetchval(
        """
        update public.generation_jobs
           set progress_stage = 'queued'
         where media_id = $1 and user_id = $2 and status = 'pending'
        returning id
        """,
        media_id,
        user_id,
    )
    if job_id is None:
        job_id = await connection.fetchval(
            """
            insert into public.generation_jobs
                (user_id, media_id, job_type, status, progress_stage, idempotency_key)
            values ($1, $2, 'garment_extraction', 'pending', 'queued', $3)
            returning id
            """,
            user_id,
            media_id,
            f"extract:{media_id}",
        )
    if not isinstance(job_id, uuid.UUID):
        raise APIError(
            503,
            ErrorCode.SERVICE_UNAVAILABLE,
            "We couldn't finish the upload. Please try again.",
            retryable=True,
        )
    return job_id


async def claim_job(connection: DBConnection, job_id: uuid.UUID, user_id: uuid.UUID) -> dict[str, Any] | None:
    row = await connection.fetchrow(
        """
        update public.generation_jobs
           set status = 'running',
               started_at = coalesce(started_at, now()),
               attempt_count = attempt_count + 1,
               progress_stage = 'extracting'
         where id = $1 and user_id = $2 and status in ('pending', 'failed')
           and attempt_count < 5
        returning id, media_id, status, attempt_count
        """,
        job_id,
        user_id,
    )
    return dict(row) if row else None


async def fetch_media(connection: DBConnection, user_id: uuid.UUID, media_id: uuid.UUID) -> dict[str, Any]:
    row = await connection.fetchrow(
        """
        select id, user_id, object_key, media_type, content_type, processing_status, created_at
          from public.wardrobe_media
         where id = $1 and user_id = $2
        """,
        media_id,
        user_id,
    )
    if row is None:
        raise not_found("upload")
    return dict(row)


async def mark_media_processing(connection: DBConnection, media_id: uuid.UUID) -> None:
    await connection.execute(
        "update public.wardrobe_media set processing_status = 'processing' where id = $1",
        media_id,
    )


async def complete_extraction(
    connection: DBConnection,
    *,
    user_id: uuid.UUID,
    media_id: uuid.UUID,
    job_id: uuid.UUID,
    object_key: str,
    garments: list[ExtractedGarment] | None = None,
    note_code: str | None = None,
) -> list[uuid.UUID]:
    """Stores proposed garments (or one unlabelled draft) unconfirmed, then marks the job ready.

    ``note_code`` records why a draft needs manual labelling (e.g. the provider failed) without
    failing the user's upload.
    """
    proposals = garments or [ExtractedGarment(category=GarmentCategory.UNCATEGORISED)]
    garment_ids: list[uuid.UUID] = []
    for proposal in proposals:
        garment_id: uuid.UUID = await connection.fetchval(
            """
            insert into public.garments
                (user_id, media_id, category, subcategory, primary_color, secondary_colors, pattern,
                 material, silhouette, formality, season_tags, style_tags, image_object_key,
                 confidence, user_confirmed)
            values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, false)
            returning id
            """,
            user_id,
            media_id,
            proposal.category.value,
            proposal.subcategory,
            proposal.primary_color,
            list(proposal.secondary_colors),
            proposal.pattern,
            proposal.material,
            proposal.silhouette,
            proposal.formality.value if proposal.formality else None,
            list(proposal.season_tags),
            list(proposal.style_tags),
            object_key,
            proposal.confidence,
        )
        garment_ids.append(garment_id)
    await connection.execute(
        "update public.wardrobe_media set processing_status = 'ready' where id = $1",
        media_id,
    )
    await connection.execute(
        """
        update public.generation_jobs
           set status = 'succeeded',
               progress_stage = 'ready_for_review',
               completed_at = now(),
               error_code = $2
         where id = $1
        """,
        job_id,
        note_code,
    )
    return garment_ids


async def fail_job(connection: DBConnection, *, job_id: uuid.UUID, media_id: uuid.UUID, error_code: str) -> None:
    await connection.execute(
        """
        update public.generation_jobs
           set status = 'failed',
               progress_stage = 'failed',
               error_code = $2,
               completed_at = now()
         where id = $1
        """,
        job_id,
        error_code,
    )
    await connection.execute(
        "update public.wardrobe_media set processing_status = 'failed', error_code = $2 where id = $1",
        media_id,
        error_code,
    )


async def list_media(connection: DBConnection, user_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await connection.fetch(
        """
        select id, media_type, content_type, processing_status, created_at
          from public.wardrobe_media
         where user_id = $1 and retention_status = 'active'
         order by created_at desc
        """,
        user_id,
    )
    return [dict(row) for row in rows]


async def list_jobs(connection: DBConnection, user_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await connection.fetch(
        """
        select id, media_id, job_type, status, progress_stage, error_code, created_at, completed_at
          from public.generation_jobs
         where user_id = $1
         order by created_at desc
         limit 50
        """,
        user_id,
    )
    return [dict(row) for row in rows]


async def list_garments(connection: DBConnection, user_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await connection.fetch(
        """
        select id, media_id, category, subcategory, primary_color, secondary_colors, pattern,
               material, silhouette, formality, season_tags, style_tags, image_object_key,
               confidence, user_confirmed, created_at, updated_at
          from public.garments
         where user_id = $1
         order by user_confirmed asc, created_at desc
        """,
        user_id,
    )
    return [dict(row) for row in rows]


async def update_garment(
    connection: DBConnection, user_id: uuid.UUID, garment_id: uuid.UUID, fields: dict[str, Any]
) -> dict[str, Any]:
    if not fields:
        row = await connection.fetchrow(
            "select * from public.garments where id = $1 and user_id = $2", garment_id, user_id
        )
        if row is None:
            raise not_found("piece")
        return dict(row)

    assignments: list[str] = []
    values: list[Any] = [garment_id, user_id]
    for key, value in fields.items():
        values.append(value.value if isinstance(value, (GarmentCategory, Formality, MediaType)) else value)
        assignments.append(f"{key} = ${len(values)}")

    row = await connection.fetchrow(
        f"""
        update public.garments
           set {", ".join(assignments)}
         where id = $1 and user_id = $2
        returning id, media_id, category, subcategory, primary_color, secondary_colors, pattern,
                  material, silhouette, formality, season_tags, style_tags, image_object_key,
                  confidence, user_confirmed, created_at, updated_at
        """,
        *values,
    )
    if row is None:
        raise not_found("piece")
    return dict(row)


async def delete_garment(connection: DBConnection, user_id: uuid.UUID, garment_id: uuid.UUID) -> str:
    row = await connection.fetchrow(
        """
        delete from public.garments
         where id = $1 and user_id = $2
        returning image_object_key
        """,
        garment_id,
        user_id,
    )
    if row is None:
        raise not_found("piece")
    return str(row["image_object_key"])


async def confirm_garments(connection: DBConnection, user_id: uuid.UUID, garment_ids: list[uuid.UUID] | None) -> int:
    if garment_ids is not None and len(garment_ids) == 0:
        return 0
    if garment_ids is None:
        result = await connection.execute(
            """
            update public.garments
               set user_confirmed = true
             where user_id = $1 and user_confirmed = false
               and category <> 'uncategorised'
            """,
            user_id,
        )
    else:
        result = await connection.execute(
            """
            update public.garments
               set user_confirmed = true
             where user_id = $1 and id = any($2::uuid[])
               and category <> 'uncategorised'
            """,
            user_id,
            garment_ids,
        )
    # asyncpg returns "UPDATE N"
    return int(result.split()[-1])


async def list_object_keys_for_user(connection: DBConnection, user_id: uuid.UUID) -> list[str]:
    rows = await connection.fetch(
        "select object_key from public.wardrobe_media where user_id = $1",
        user_id,
    )
    media_keys = [str(row["object_key"]) for row in rows]
    garment_rows = await connection.fetch(
        "select image_object_key from public.garments where user_id = $1",
        user_id,
    )
    garment_keys = [str(row["image_object_key"]) for row in garment_rows]
    avatar_rows = await connection.fetch(
        "select face_object_key from public.avatar_profiles where user_id = $1 and face_object_key is not null",
        user_id,
    )
    avatar_keys = [str(row["face_object_key"]) for row in avatar_rows]
    render_rows = await connection.fetch(
        "select object_key from public.outfit_renders where user_id = $1 and object_key is not null",
        user_id,
    )
    render_keys = [str(row["object_key"]) for row in render_rows]
    return sorted(set(media_keys + garment_keys + avatar_keys + render_keys))


def parse_status(value: str) -> MediaProcessingStatus:
    return MediaProcessingStatus(value)


def parse_job_status(value: str) -> JobStatus:
    return JobStatus(value)


def parse_category(value: str) -> GarmentCategory:
    return GarmentCategory(value)
