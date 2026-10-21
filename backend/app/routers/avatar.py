from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter

from app import avatar as avatar_repo
from app import entitlements
from app import outfits as outfits_repo
from app import renders as renders_repo
from app.avatar_models import (
    AvatarFaceUploadResponse,
    AvatarProfileResponse,
    TryOnSessionResponse,
    TryOnStatus,
    TryOnViewResponse,
    UpsertAvatarProfileRequest,
)
from app.dependencies import CurrentUser, Services, ServicesDep
from app.errors import APIError, ErrorCode
from app.storage import UPLOAD_URL_TTL_SECONDS, with_media_version

router = APIRouter(tags=["avatar"])


async def _response(services: Services, row: dict[str, Any]) -> AvatarProfileResponse:
    face_key = row.get("face_object_key")
    face_url = None
    if face_key:
        face_url = with_media_version(
            await services.storage.create_signed_read_url(str(face_key)),
            row.get("updated_at"),
        )
    return AvatarProfileResponse(
        height_cm=int(row["height_cm"]),
        body_build=avatar_repo.parse_body_build(row["body_build"]),
        has_face=bool(face_key),
        face_url=face_url,
        updated_at=row.get("updated_at"),
    )


@router.get("/v1/me/avatar", response_model=AvatarProfileResponse)
async def get_avatar(user: CurrentUser, services: ServicesDep) -> AvatarProfileResponse:
    async with services.database.as_user(user.claims) as connection:
        row = await avatar_repo.fetch_avatar(connection, user.id)
    if row is None:
        raise APIError(404, ErrorCode.NOT_FOUND, "No avatar profile yet.", retryable=False)
    return await _response(services, row)


@router.put("/v1/me/avatar", response_model=AvatarProfileResponse)
async def put_avatar(
    body: UpsertAvatarProfileRequest, user: CurrentUser, services: ServicesDep
) -> AvatarProfileResponse:
    async with services.database.as_user(user.claims) as connection:
        row = await avatar_repo.upsert_avatar(connection, user.id, body)
    return await _response(services, row)


@router.post("/v1/me/avatar/face/upload", response_model=AvatarFaceUploadResponse)
async def create_face_upload(user: CurrentUser, services: ServicesDep) -> AvatarFaceUploadResponse:
    async with services.database.as_user(user.claims) as connection:
        existing = await avatar_repo.fetch_avatar(connection, user.id)
    if existing is None:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            "Save your height and body build before adding a face photo.",
            retryable=False,
        )
    object_key = avatar_repo.face_object_key(user.id)
    # Replacing a face photo reuses a fixed key; Storage rejects a second signed upload
    # while the prior object still exists, so clear it first.
    if existing.get("face_object_key"):
        await services.storage.remove_objects([str(existing["face_object_key"])])
    elif await services.storage.object_exists(object_key):
        await services.storage.remove_objects([object_key])
    upload_url = await services.storage.create_signed_upload_url(object_key)
    return AvatarFaceUploadResponse(
        object_key=object_key,
        upload_url=upload_url,
        expires_in_seconds=UPLOAD_URL_TTL_SECONDS,
    )


@router.post("/v1/me/avatar/face/complete", response_model=AvatarProfileResponse)
async def complete_face_upload(user: CurrentUser, services: ServicesDep) -> AvatarProfileResponse:
    object_key = avatar_repo.face_object_key(user.id)
    exists = await services.storage.object_exists(object_key)
    if not exists:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            "Upload your face photo before confirming.",
            retryable=False,
        )
    async with services.database.as_user(user.claims) as connection:
        row = await avatar_repo.set_face_object_key(connection, user.id, object_key)
    return await _response(services, row)


async def _try_on_context(
    look_id: uuid.UUID, user: CurrentUser, services: Services
) -> tuple[dict[str, Any], dict[str, Any], entitlements.Plan]:
    async with services.database.as_user(user.claims) as connection:
        avatar = await avatar_repo.fetch_avatar(connection, user.id)
        if avatar is None:
            raise APIError(
                422,
                ErrorCode.INVALID_REQUEST,
                "Add your height, body build, and face photo before trying on a look.",
                retryable=False,
            )
        if not avatar.get("face_object_key"):
            raise APIError(
                422,
                ErrorCode.INVALID_REQUEST,
                "Add a clear face photo so Grymode can build your personal preview.",
                retryable=False,
            )
        outfit = await outfits_repo.fetch_outfit(connection, user.id, look_id)
        snap = await entitlements.entitlement_snapshot(connection, user.id)

    plan = snap["plan"]
    if not entitlements.can_open_outfit(plan=plan, is_free_reveal=bool(outfit["is_free_reveal"])):
        raise APIError(
            403,
            ErrorCode.FORBIDDEN,
            "Unlock Grymode to try on looks from your full library.",
            retryable=False,
        )
    return avatar, outfit, plan


def _session_status(rows: list[dict[str, Any]]) -> TryOnStatus:
    if not rows:
        return "idle"
    statuses = {row["view"]: row["status"] for row in rows}
    if any(s in ("pending", "running") for s in statuses.values()):
        return "rendering"
    if all(statuses.get(view) == "succeeded" for view in renders_repo.TRY_ON_VIEWS):
        return "ready"
    if statuses.get(renders_repo.VIEW_FRONT) == "succeeded":
        return "partial"
    return "failed"


async def _session(
    look_id: uuid.UUID, user: CurrentUser, services: Services, avatar: dict[str, Any], outfit: dict[str, Any]
) -> TryOnSessionResponse:
    async with services.database.as_service() as connection:
        pieces = await outfits_repo.list_outfit_garments(connection, user.id, [look_id])
        render_rows = (
            await renders_repo.list_renders(connection, user.id, [look_id], renders_repo.KIND_TRY_ON)
            if services.renders is not None
            else []
        )
    order = {view: index for index, view in enumerate(renders_repo.TRY_ON_VIEWS)}
    render_rows.sort(key=lambda r: order.get(r["view"], len(order)))
    face_key = str(avatar["face_object_key"])
    garment_keys = [str(p["image_object_key"]) for p in sorted(pieces, key=lambda p: p["position"])]
    render_keys = [str(r["object_key"]) for r in render_rows if r["object_key"]]
    signed = await services.storage.create_signed_read_urls([face_key, *garment_keys, *render_keys])
    face_url = signed.get(face_key)
    if face_url:
        face_url = with_media_version(face_url, avatar.get("updated_at"))

    base = {
        "look_id": str(look_id),
        "title": outfit["title"],
        "height_cm": int(avatar["height_cm"]),
        "body_build": avatar_repo.parse_body_build(avatar["body_build"]),
        "face_url": face_url,
        "garment_image_urls": [signed[k] for k in garment_keys if k in signed],
    }
    if services.renders is None:
        return TryOnSessionResponse(**base)
    views = [
        TryOnViewResponse(
            view=row["view"],
            status=row["status"],
            image_url=(
                with_media_version(signed[str(row["object_key"])], row.get("updated_at"))
                if row["object_key"] and str(row["object_key"]) in signed
                else None
            ),
            error_code=row["error_code"],
        )
        for row in render_rows
    ]
    return TryOnSessionResponse(
        **base,
        preview_mode="ai_multi_view",
        status=_session_status(render_rows),
        views=views,
        notice="AI-rendered from your face photo, height, and build, wearing this look's exact pieces.",
    )


@router.get("/v1/try-on/looks/{look_id}", response_model=TryOnSessionResponse)
async def try_on_look(look_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> TryOnSessionResponse:
    avatar, outfit, _plan = await _try_on_context(look_id, user, services)
    return await _session(look_id, user, services, avatar, outfit)


@router.post("/v1/try-on/looks/{look_id}", response_model=TryOnSessionResponse)
async def start_try_on(look_id: uuid.UUID, user: CurrentUser, services: ServicesDep) -> TryOnSessionResponse:
    """Starts the four-angle render, or reuses a cache hit for the same face + look signature."""
    avatar, outfit, plan = await _try_on_context(look_id, user, services)
    if services.renders is not None:
        await services.renders.ensure_try_on(
            user.id,
            look_id,
            avatar,
            plan=plan,
            outfit_signature=str(outfit["signature"]),
        )
    return await _session(look_id, user, services, avatar, outfit)
