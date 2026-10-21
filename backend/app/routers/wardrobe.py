from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any

from fastapi import APIRouter, Response

from app import wardrobe
from app.dependencies import CurrentUser, Services, ServicesDep
from app.errors import APIError, ErrorCode
from app.extraction import run_extraction_job
from app.storage import READ_URL_TTL_SECONDS, UPLOAD_URL_TTL_SECONDS
from app.wardrobe_models import (
    CompleteUploadResponse,
    ConfirmWardrobeRequest,
    ConfirmWardrobeResponse,
    CreateUploadRequest,
    Formality,
    GarmentCategory,
    GarmentResponse,
    JobResponse,
    JobStatus,
    MediaProcessingStatus,
    MediaType,
    UpdateGarmentRequest,
    UploadSlotResponse,
    WardrobeMediaResponse,
    WardrobeSummaryResponse,
)

router = APIRouter(tags=["wardrobe"])
logger = logging.getLogger("grymode.wardrobe")
_background_tasks: set[asyncio.Task[None]] = set()


def _media_response(row: dict[str, Any]) -> WardrobeMediaResponse:
    return WardrobeMediaResponse(
        id=row["id"],
        media_type=MediaType(row["media_type"]),
        content_type=row["content_type"],
        processing_status=MediaProcessingStatus(row["processing_status"]),
        created_at=row["created_at"],
    )


def _job_response(row: dict[str, Any]) -> JobResponse:
    return JobResponse(
        id=row["id"],
        media_id=row["media_id"],
        job_type="garment_extraction",
        status=JobStatus(row["status"]),
        progress_stage=row["progress_stage"],
        error_code=row["error_code"],
        created_at=row["created_at"],
        completed_at=row["completed_at"],
    )


async def _garment_response(services: Services, row: dict[str, Any]) -> GarmentResponse:
    image_url = await services.storage.create_signed_read_url(str(row["image_object_key"]))
    formality = Formality(row["formality"]) if row["formality"] else None
    return GarmentResponse(
        id=row["id"],
        media_id=row["media_id"],
        category=GarmentCategory(row["category"]),
        subcategory=row["subcategory"],
        primary_color=row["primary_color"],
        secondary_colors=list(row["secondary_colors"] or []),
        pattern=row["pattern"],
        material=row["material"],
        silhouette=row["silhouette"],
        formality=formality,
        season_tags=list(row["season_tags"] or []),
        style_tags=list(row["style_tags"] or []),
        image_url=image_url,
        confidence=row["confidence"],
        user_confirmed=row["user_confirmed"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


@router.post("/v1/wardrobe/uploads", response_model=UploadSlotResponse)
async def create_upload(body: CreateUploadRequest, user: CurrentUser, services: ServicesDep) -> UploadSlotResponse:
    async with services.database.as_user(user.claims) as connection:
        media_id, object_key, job_id = await wardrobe.create_upload_slot(connection, user, body)
    upload_url = await services.storage.create_signed_upload_url(object_key)
    return UploadSlotResponse(
        media_id=media_id,
        object_key=object_key,
        upload_url=upload_url,
        expires_in_seconds=UPLOAD_URL_TTL_SECONDS,
        job_id=job_id,
    )


@router.post("/v1/wardrobe/uploads/{media_id}/complete", response_model=CompleteUploadResponse)
async def complete_upload(media_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> CompleteUploadResponse:
    async with services.database.as_user(user.claims) as connection:
        media = await wardrobe.fetch_media(connection, user.id, media_id)
        if media["processing_status"] not in (
            MediaProcessingStatus.AWAITING_UPLOAD.value,
            MediaProcessingStatus.UPLOADED.value,
        ):
            job = await connection.fetchrow(
                """
                select id from public.generation_jobs
                 where media_id = $1 and user_id = $2
                 order by created_at desc limit 1
                """,
                media_id,
                user.id,
            )
            return CompleteUploadResponse(
                media_id=media_id,
                processing_status=MediaProcessingStatus(media["processing_status"]),
                job_id=job["id"] if job else uuid.uuid4(),
            )

    exists = await services.storage.object_exists(media["object_key"])
    if not exists:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            "We couldn't find the uploaded file yet. Wait a moment and try again.",
            retryable=True,
        )

    async with services.database.as_user(user.claims) as connection:
        job_id = await wardrobe.mark_uploaded(connection, user.id, media_id)

    task = asyncio.create_task(
        run_extraction_job(
            database=services.database,
            extractor=services.extractor,
            user_id=user.id,
            media_id=media_id,
            object_key=str(media["object_key"]),
        )
    )
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
    return CompleteUploadResponse(
        media_id=media_id,
        processing_status=MediaProcessingStatus.UPLOADED,
        job_id=job_id,
    )


@router.get("/v1/wardrobe", response_model=WardrobeSummaryResponse)
async def get_wardrobe(user: CurrentUser, services: ServicesDep) -> WardrobeSummaryResponse:
    async with services.database.as_user(user.claims) as connection:
        media_rows = await wardrobe.list_media(connection, user.id)
        garment_rows = await wardrobe.list_garments(connection, user.id)
        job_rows = await wardrobe.list_jobs(connection, user.id)

    garments = [await _garment_response(services, row) for row in garment_rows]
    confirmed = sum(1 for g in garments if g.user_confirmed)
    return WardrobeSummaryResponse(
        media=[_media_response(row) for row in media_rows],
        garments=garments,
        jobs=[_job_response(row) for row in job_rows],
        unconfirmed_count=len(garments) - confirmed,
        confirmed_count=confirmed,
    )


@router.get("/v1/wardrobe/jobs/{job_id}", response_model=JobResponse)
async def get_job(job_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> JobResponse:
    async with services.database.as_user(user.claims) as connection:
        row = await connection.fetchrow(
            """
            select id, media_id, job_type, status, progress_stage, error_code, created_at, completed_at
              from public.generation_jobs
             where id = $1 and user_id = $2
            """,
            job_id,
            user.id,
        )
    if row is None:
        raise wardrobe.not_found("job")
    return _job_response(dict(row))


@router.patch("/v1/wardrobe/garments/{garment_id}", response_model=GarmentResponse)
async def patch_garment(
    garment_id: uuid.UUID, body: UpdateGarmentRequest, user: CurrentUser, services: ServicesDep
) -> GarmentResponse:
    fields = body.model_dump(exclude_unset=True)
    async with services.database.as_user(user.claims) as connection:
        row = await wardrobe.update_garment(connection, user.id, garment_id, fields)
    return await _garment_response(services, row)


@router.delete("/v1/wardrobe/garments/{garment_id}", status_code=204, response_class=Response)
async def remove_garment(garment_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> Response:
    async with services.database.as_user(user.claims) as connection:
        object_key = await wardrobe.delete_garment(connection, user.id, garment_id)
    # Best-effort object cleanup; the DB row is already gone.
    try:
        await services.storage.remove_objects([object_key])
    except APIError:
        logger.warning("garment_object_cleanup_deferred", extra={"garment_id": str(garment_id)})
    return Response(status_code=204)


@router.post("/v1/wardrobe/confirm", response_model=ConfirmWardrobeResponse)
async def confirm_wardrobe(
    body: ConfirmWardrobeRequest, user: CurrentUser, services: ServicesDep
) -> ConfirmWardrobeResponse:
    async with services.database.as_user(user.claims) as connection:
        count = await wardrobe.confirm_garments(connection, user.id, body.garment_ids)
    if count == 0:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            "Choose a category for each piece before confirming it.",
        )
    return ConfirmWardrobeResponse(confirmed_count=count)


# Exported for tests / docs; signed URL TTL is part of the contract clients may display.
SIGNED_READ_TTL = READ_URL_TTL_SECONDS
