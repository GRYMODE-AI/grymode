from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Query, Response

from app import entitlements, profiles
from app import outfits as outfits_repo
from app import renders as renders_repo
from app.dependencies import CurrentUser, Services, ServicesDep
from app.errors import APIError, ErrorCode
from app.models import StyleProfile
from app.outfit_generator import run_outfit_generation_job
from app.outfit_models import (
    EntitlementResponse,
    HomeResponse,
    OutfitGarmentRef,
    OutfitJobResponse,
    OutfitLibraryResponse,
    OutfitResponse,
    OutfitSlot,
    OutfitVisualResponse,
    StartOutfitGenerationResponse,
)
from app.storage import with_media_version
from app.wardrobe_models import GarmentCategory, JobStatus

router = APIRouter(tags=["outfits"])
logger = logging.getLogger("grymode.outfits")
_background_tasks: set[asyncio.Task[None]] = set()


def _job_response(row: dict[str, Any], accepted_count: int) -> OutfitJobResponse:
    return OutfitJobResponse(
        id=row["id"],
        status=JobStatus(row["status"]),
        progress_stage=row["progress_stage"],
        error_code=row["error_code"],
        accepted_count=accepted_count,
        created_at=row["created_at"],
        completed_at=row["completed_at"],
    )


def _entitlement_response(snapshot: dict[str, Any]) -> EntitlementResponse:
    return EntitlementResponse(
        plan=snapshot["plan"],
        can_open_full_library=bool(snapshot["can_open_full_library"]),
    )


def _garment_refs(piece_rows: list[dict[str, Any]], signed: dict[str, str]) -> list[OutfitGarmentRef]:
    return [
        OutfitGarmentRef(
            garment_id=piece["garment_id"],
            category=GarmentCategory(piece["category"]),
            slot=OutfitSlot(piece["slot"]),
            position=piece["position"],
            image_url=signed.get(str(piece["image_object_key"]), ""),
            primary_color=piece["primary_color"],
            subcategory=piece.get("subcategory"),
            material=piece.get("material"),
        )
        for piece in piece_rows
    ]


def _visual_response(render: dict[str, Any] | None, signed: dict[str, str]) -> OutfitVisualResponse | None:
    if render is None:
        return None
    raw = signed.get(str(render["object_key"])) if render["object_key"] else None
    url = with_media_version(raw, render.get("updated_at")) if raw else None
    status = render["status"]
    if status == "succeeded" and not url:
        return None
    return OutfitVisualResponse(status=status, image_url=url, error_code=render["error_code"])


async def _build_responses(
    services: Services,
    user_id: uuid.UUID,
    rows: list[dict[str, Any]],
    pieces_by_outfit: dict[uuid.UUID, list[dict[str, Any]]],
    *,
    plan: entitlements.Plan,
    saved_ids: set[uuid.UUID],
) -> list[OutfitResponse]:
    """Signs every unlocked garment photo and look visual in one Storage call."""
    unlocked_ids = [
        row["id"] for row in rows if entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"]))
    ]
    async with services.database.as_service() as connection:
        render_rows = await renders_repo.list_renders(connection, user_id, unlocked_ids, renders_repo.KIND_LOOK)
    visuals = {r["outfit_id"]: r for r in render_rows if r["view"] == renders_repo.VIEW_FRONT}
    keys = [str(p["image_object_key"]) for oid in unlocked_ids for p in pieces_by_outfit.get(oid, [])]
    keys += [str(r["object_key"]) for r in visuals.values() if r["object_key"]]
    signed = await services.storage.create_signed_read_urls(keys) if keys else {}
    return [
        _outfit_response(
            row,
            pieces_by_outfit.get(row["id"], []),
            plan=plan,
            is_saved=row["id"] in saved_ids,
            signed=signed,
            visual=_visual_response(visuals.get(row["id"]), signed),
        )
        for row in rows
    ]


async def _single_response(
    services: Services, user_id: uuid.UUID, row: dict[str, Any], *, plan: entitlements.Plan, is_saved: bool
) -> OutfitResponse:
    async with services.database.as_service() as connection:
        piece_rows = await outfits_repo.list_outfit_garments(connection, user_id, [row["id"]])
    saved = {row["id"]} if is_saved else set()
    [response] = await _build_responses(services, user_id, [row], {row["id"]: piece_rows}, plan=plan, saved_ids=saved)
    return response


def _outfit_response(
    row: dict[str, Any],
    piece_rows: list[dict[str, Any]],
    *,
    plan: entitlements.Plan,
    is_saved: bool,
    signed: dict[str, str],
    visual: OutfitVisualResponse | None,
) -> OutfitResponse:
    unlocked = entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"]))
    if unlocked:
        garments = _garment_refs(piece_rows, signed)
        return OutfitResponse(
            id=row["id"],
            title=row["title"],
            occasion_tags=list(row["occasion_tags"] or []),
            style_tags=list(row["style_tags"] or []),
            contextual_tags=list(row["contextual_tags"] or []),
            score=float(row["score"]),
            is_free_reveal=bool(row["is_free_reveal"]),
            is_locked=False,
            is_saved=is_saved,
            piece_count=len(piece_rows),
            garments=garments,
            visual=visual,
            created_at=row["created_at"],
        )
    # Locked: truthful preview only — titles/tags/counts, no media, no score.
    return OutfitResponse(
        id=row["id"],
        title=row["title"],
        occasion_tags=list(row["occasion_tags"] or []),
        style_tags=list(row["style_tags"] or []),
        contextual_tags=list(row["contextual_tags"] or []),
        score=None,
        is_free_reveal=bool(row["is_free_reveal"]),
        is_locked=True,
        is_saved=is_saved,
        piece_count=len(piece_rows),
        garments=[],
        created_at=row["created_at"],
    )


async def _generate_then_render(services: Services, user_id: uuid.UUID, job_id: uuid.UUID, style: StyleProfile) -> None:
    renders = services.renders
    previous_keys: set[str] = set()
    if renders is not None:
        async with services.database.as_service() as connection:
            previous_keys = set(await renders_repo.render_object_keys(connection, user_id))

    await run_outfit_generation_job(
        database=services.database,
        composer=services.outfit_composer,
        user_id=user_id,
        job_id=job_id,
        style_profile=style,
    )
    if renders is None:
        return

    async with services.database.as_service() as connection:
        job = await outfits_repo.fetch_outfit_job(connection, user_id, job_id)
        current_keys = set(await renders_repo.render_object_keys(connection, user_id))
        rows = await outfits_repo.list_outfits(connection, user_id)
        snap = await entitlements.entitlement_snapshot(connection, user_id)
    # Regeneration replaces the library; renders of removed looks cascade away in the DB.
    stale = sorted(previous_keys - current_keys)
    if stale:
        try:
            await services.storage.remove_objects(stale)
        except Exception:
            logger.warning("render_cleanup_failed", extra={"job_id": str(job_id), "count": len(stale)})
    if job["status"] != "succeeded" or not services.settings.ai_render_looks_after_generation:
        return
    unlocked = [
        row["id"]
        for row in rows
        if entitlements.can_open_outfit(plan=snap["plan"], is_free_reveal=bool(row["is_free_reveal"]))
    ]
    renders.schedule_looks(user_id, unlocked, plan=snap["plan"])


def _schedule(services: Services, user_id: uuid.UUID, job_id: uuid.UUID, style: StyleProfile) -> None:
    task = asyncio.create_task(_generate_then_render(services, user_id, job_id, style))
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)


def _filter_library_rows(
    rows: list[dict[str, Any]],
    *,
    occasion: str | None,
    saved_only: bool,
    saved_ids: set[uuid.UUID],
) -> list[dict[str, Any]]:
    filtered = rows
    if occasion:
        needle = occasion.strip().lower()
        filtered = [
            row for row in filtered if any(str(tag).lower() == needle for tag in (row.get("occasion_tags") or []))
        ]
    if saved_only:
        filtered = [row for row in filtered if row["id"] in saved_ids]
    return filtered


@router.post("/v1/outfits/generate", response_model=StartOutfitGenerationResponse)
async def start_generation(user: CurrentUser, services: ServicesDep) -> StartOutfitGenerationResponse:
    async with services.database.as_user(user.claims) as connection:
        garments = await outfits_repo.list_confirmed_garments(connection, user.id)
        if len(garments) < outfits_repo.MIN_CONFIRMED_GARMENTS:
            raise APIError(
                422,
                ErrorCode.INVALID_REQUEST,
                "Confirm at least two labelled wardrobe pieces before generating looks.",
                retryable=False,
            )
        fingerprint = outfits_repo.wardrobe_fingerprint([g["id"] for g in garments])
        idempotency_key = f"outfit_gen:{services.outfit_composer.version}:{fingerprint}"

        active = await outfits_repo.find_active_outfit_job(connection, user.id)
        if active is not None:
            accepted = await outfits_repo.count_accepted_outfits(connection, user.id)
            return StartOutfitGenerationResponse(
                job=_job_response(active, accepted),
                reused_existing=True,
            )

        existing = await outfits_repo.find_job_by_idempotency(connection, user.id, idempotency_key)
        if existing is not None and existing["status"] == "succeeded":
            accepted = await outfits_repo.count_accepted_outfits(connection, user.id)
            return StartOutfitGenerationResponse(
                job=_job_response(existing, accepted),
                reused_existing=True,
            )

        job = await outfits_repo.create_outfit_job(connection, user.id, idempotency_key)
        if job["status"] != "pending":
            accepted = await outfits_repo.count_accepted_outfits(connection, user.id)
            return StartOutfitGenerationResponse(
                job=_job_response(job, accepted),
                reused_existing=True,
            )
        profile = await profiles.fetch_profile(connection, user)

    style = profile.style_profile
    _schedule(services, user.id, job["id"], style)
    return StartOutfitGenerationResponse(job=_job_response(job, accepted_count=0), reused_existing=False)


@router.get("/v1/outfits/jobs/{job_id}", response_model=OutfitJobResponse)
async def get_job(job_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> OutfitJobResponse:
    async with services.database.as_user(user.claims) as connection:
        row = await outfits_repo.fetch_outfit_job(connection, user.id, job_id)
        accepted = await outfits_repo.count_accepted_outfits(connection, user.id)
    return _job_response(row, accepted)


@router.get("/v1/home", response_model=HomeResponse)
async def get_home(user: CurrentUser, services: ServicesDep) -> HomeResponse:
    day_key = datetime.now(UTC).date().isoformat()
    async with services.database.as_user(user.claims) as connection:
        rows = await outfits_repo.list_outfits(connection, user.id)
        saved_ids = await outfits_repo.list_saved_outfit_ids(connection, user.id)
        saved_count = len(saved_ids)
        wardrobe_count = await outfits_repo.count_confirmed_garments(connection, user.id)
        snap = await entitlements.entitlement_snapshot(connection, user.id)

    plan = snap["plan"]
    accepted = len(rows)
    todays_row = outfits_repo.pick_todays_look(rows, user_id=user.id, day_key=day_key, plan=plan)
    locked_count = sum(
        1 for row in rows if not entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"]))
    )

    todays_look: OutfitResponse | None = None
    if todays_row is not None:
        todays_look = await _single_response(
            services, user.id, todays_row, plan=plan, is_saved=todays_row["id"] in saved_ids
        )

    return HomeResponse(
        todays_look=todays_look,
        accepted_count=accepted,
        saved_count=saved_count,
        locked_count=locked_count,
        entitlement=_entitlement_response(snap),
        wardrobe_confirmed_count=wardrobe_count,
    )


@router.get("/v1/outfits", response_model=OutfitLibraryResponse)
async def list_library(
    user: CurrentUser,
    services: ServicesDep,
    occasion: str | None = Query(default=None, min_length=1, max_length=64),
    saved_only: bool = Query(default=False),
) -> OutfitLibraryResponse:
    async with services.database.as_user(user.claims) as connection:
        rows = await outfits_repo.list_outfits(connection, user.id)
        saved_ids = await outfits_repo.list_saved_outfit_ids(connection, user.id)
        active = await outfits_repo.find_active_outfit_job(connection, user.id)
        latest = active or await outfits_repo.latest_outfit_job(connection, user.id)
        snap = await entitlements.entitlement_snapshot(connection, user.id)

    plan = snap["plan"]
    accepted = len(rows)
    filter_occasions = outfits_repo.occasion_filter_values(rows)
    filtered = _filter_library_rows(rows, occasion=occasion, saved_only=saved_only, saved_ids=saved_ids)

    outfit_ids = [row["id"] for row in filtered]
    async with services.database.as_service() as connection:
        piece_rows = await outfits_repo.list_outfit_garments(connection, user.id, outfit_ids)
    pieces_by_outfit: dict[uuid.UUID, list[dict[str, Any]]] = {}
    for piece in piece_rows:
        pieces_by_outfit.setdefault(piece["outfit_id"], []).append(piece)

    outfits = await _build_responses(services, user.id, filtered, pieces_by_outfit, plan=plan, saved_ids=saved_ids)
    locked_count = sum(
        1 for row in rows if not entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"]))
    )
    job = _job_response(latest, accepted) if latest else None
    return OutfitLibraryResponse(
        accepted_count=accepted,
        locked_count=locked_count,
        saved_count=len(saved_ids),
        entitlement=_entitlement_response(snap),
        filter_occasions=filter_occasions,
        outfits=outfits,
        active_job=job,
    )


@router.post("/v1/outfits/{outfit_id}/save", response_model=OutfitResponse)
async def save_outfit(outfit_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> OutfitResponse:
    async with services.database.as_user(user.claims) as connection:
        row = await outfits_repo.fetch_outfit(connection, user.id, outfit_id)
        snap = await entitlements.entitlement_snapshot(connection, user.id)
        plan = snap["plan"]
        if not entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"])):
            raise APIError(
                403,
                ErrorCode.FORBIDDEN,
                "Unlock Grymode to save looks from your full library.",
                retryable=False,
            )
        await outfits_repo.save_look(connection, user.id, outfit_id)

    return await _single_response(services, user.id, row, plan=plan, is_saved=True)


@router.delete("/v1/outfits/{outfit_id}/save", status_code=204, response_class=Response)
async def unsave_outfit(outfit_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> Response:
    async with services.database.as_user(user.claims) as connection:
        await outfits_repo.fetch_outfit(connection, user.id, outfit_id)
        await outfits_repo.unsave_look(connection, user.id, outfit_id)
    return Response(status_code=204)


@router.get("/v1/outfits/{outfit_id}", response_model=OutfitResponse)
async def get_outfit(outfit_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> OutfitResponse:
    async with services.database.as_user(user.claims) as connection:
        row = await outfits_repo.fetch_outfit(connection, user.id, outfit_id)
        snap = await entitlements.entitlement_snapshot(connection, user.id)
        saved_ids = await outfits_repo.list_saved_outfit_ids(connection, user.id)

    plan = snap["plan"]
    if not entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"])):
        raise APIError(
            403,
            ErrorCode.FORBIDDEN,
            "This look is part of your full library. Unlock Grymode to open it.",
            retryable=False,
        )

    return await _single_response(services, user.id, row, plan=plan, is_saved=outfit_id in saved_ids)


@router.post("/v1/outfits/{outfit_id}/visual", response_model=OutfitResponse)
async def request_visual(outfit_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> OutfitResponse:
    """Starts (or retries) the AI-styled image of an unlocked look; idempotent while rendering."""
    async with services.database.as_user(user.claims) as connection:
        row = await outfits_repo.fetch_outfit(connection, user.id, outfit_id)
        snap = await entitlements.entitlement_snapshot(connection, user.id)
        saved_ids = await outfits_repo.list_saved_outfit_ids(connection, user.id)

    plan = snap["plan"]
    if not entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(row["is_free_reveal"])):
        raise APIError(
            403,
            ErrorCode.FORBIDDEN,
            "This look is part of your full library. Unlock Grymode to open it.",
            retryable=False,
        )
    if services.renders is None:
        raise APIError(
            503, ErrorCode.SERVICE_UNAVAILABLE, "Styled visuals are not available right now.", retryable=True
        )
    await services.renders.ensure_look(user.id, outfit_id, plan=plan, outfit_signature=str(row["signature"]))
    return await _single_response(services, user.id, row, plan=plan, is_saved=outfit_id in saved_ids)
