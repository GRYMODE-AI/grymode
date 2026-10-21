import uuid
from typing import Any

from app.auth import AuthenticatedUser
from app.db import DBConnection
from app.errors import APIError, ErrorCode
from app.models import ProfileResponse, StyleProfile

_COLUMNS = "id, display_name, style_profile, onboarding_completed_at, created_at, updated_at"


def session_revoked() -> APIError:
    """Every auth user gets a profile row from a trigger, so a valid token without one
    belongs to an account that has been deleted."""
    return APIError(
        401,
        ErrorCode.SESSION_REVOKED,
        "This account is no longer available. Sign in again.",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def fetch_profile(connection: DBConnection, user: AuthenticatedUser) -> ProfileResponse:
    row = await connection.fetchrow(f"select {_COLUMNS} from public.profiles where id = $1", user.id)
    return _to_response(row, user)


async def update_display_name(
    connection: DBConnection, user: AuthenticatedUser, display_name: str | None
) -> ProfileResponse:
    row = await connection.fetchrow(
        f"update public.profiles set display_name = $2 where id = $1 returning {_COLUMNS}",
        user.id,
        display_name,
    )
    return _to_response(row, user)


async def update_style_profile(
    connection: DBConnection,
    user: AuthenticatedUser,
    style_profile: StyleProfile,
    *,
    onboarding_completed: bool,
) -> ProfileResponse:
    row = await connection.fetchrow(
        f"""
        update public.profiles
           set style_profile = $2,
               onboarding_completed_at = case when $3 then coalesce(onboarding_completed_at, now())
                                              else onboarding_completed_at end
         where id = $1
        returning {_COLUMNS}
        """,
        user.id,
        style_profile.model_dump(mode="json"),
        onboarding_completed,
    )
    return _to_response(row, user)


async def open_deletion_request(connection: DBConnection, user_id: uuid.UUID) -> uuid.UUID:
    request_id: uuid.UUID = await connection.fetchval(
        """
        insert into public.privacy_requests (user_id, request_type, status)
        values ($1, 'account_deletion', 'processing')
        on conflict (user_id, request_type) where status in ('pending', 'processing')
        do update set status = 'processing'
        returning id
        """,
        user_id,
    )
    return request_id


async def complete_deletion_request(connection: DBConnection, request_id: uuid.UUID) -> None:
    await connection.execute(
        "update public.privacy_requests set status = 'completed', completed_at = now() where id = $1",
        request_id,
    )


def _to_response(row: Any, user: AuthenticatedUser) -> ProfileResponse:
    if row is None:
        raise session_revoked()
    return ProfileResponse(
        id=row["id"],
        email=user.email,
        display_name=row["display_name"],
        style_profile=StyleProfile.model_validate(row["style_profile"] or {}),
        onboarding_completed_at=row["onboarding_completed_at"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )
