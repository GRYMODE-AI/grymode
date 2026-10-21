"""Persistence helpers for avatar profiles used by personal try-on previews."""

from __future__ import annotations

import uuid
from typing import Any

from app.avatar_models import BodyBuild, UpsertAvatarProfileRequest
from app.db import DBConnection
from app.errors import APIError, ErrorCode


def face_object_key(user_id: uuid.UUID) -> str:
    return f"{user_id}/avatar/face.jpg"


async def fetch_avatar(connection: DBConnection, user_id: uuid.UUID) -> dict[str, Any] | None:
    row = await connection.fetchrow(
        """
        select user_id, height_cm, body_build, face_object_key, created_at, updated_at
          from public.avatar_profiles
         where user_id = $1
        """,
        user_id,
    )
    return dict(row) if row else None


async def upsert_avatar(
    connection: DBConnection, user_id: uuid.UUID, body: UpsertAvatarProfileRequest
) -> dict[str, Any]:
    row = await connection.fetchrow(
        """
        insert into public.avatar_profiles (user_id, height_cm, body_build)
        values ($1, $2, $3)
        on conflict (user_id) do update
           set height_cm = excluded.height_cm,
               body_build = excluded.body_build
        returning user_id, height_cm, body_build, face_object_key, created_at, updated_at
        """,
        user_id,
        body.height_cm,
        body.body_build.value,
    )
    if row is None:
        raise APIError(503, ErrorCode.SERVICE_UNAVAILABLE, "Could not save avatar profile.", retryable=True)
    return dict(row)


async def set_face_object_key(connection: DBConnection, user_id: uuid.UUID, object_key: str) -> dict[str, Any]:
    existing = await fetch_avatar(connection, user_id)
    if existing is None:
        raise APIError(
            422,
            ErrorCode.INVALID_REQUEST,
            "Save your height and body build before adding a face photo.",
            retryable=False,
        )
    row = await connection.fetchrow(
        """
        update public.avatar_profiles
           set face_object_key = $2
         where user_id = $1
        returning user_id, height_cm, body_build, face_object_key, created_at, updated_at
        """,
        user_id,
        object_key,
    )
    if row is None:
        raise APIError(503, ErrorCode.SERVICE_UNAVAILABLE, "Could not save face photo.", retryable=True)
    return dict(row)


def parse_body_build(value: str) -> BodyBuild:
    return BodyBuild(value)
