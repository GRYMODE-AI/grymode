"""Server-side image usage quotas. Cache hits never increment counters."""

from __future__ import annotations

import uuid
from typing import Literal

from app.config import Settings
from app.db import DBConnection
from app.entitlements import Plan
from app.errors import APIError, ErrorCode

UsageKind = Literal["look_render", "try_on"]


def limits_for(settings: Settings, plan: Plan, kind: UsageKind) -> tuple[int, int]:
    """Returns ``(daily_limit, monthly_limit)`` for the plan and usage kind."""
    if kind == "look_render":
        if plan == "premium":
            return settings.ai_look_render_daily_premium, settings.ai_look_render_monthly_premium
        return settings.ai_look_render_daily_free, settings.ai_look_render_monthly_free
    if plan == "premium":
        return settings.ai_try_on_daily_premium, settings.ai_try_on_monthly_premium
    return settings.ai_try_on_daily_free, settings.ai_try_on_monthly_free


async def used_today(connection: DBConnection, user_id: uuid.UUID, kind: UsageKind) -> int:
    value = await connection.fetchval(
        """
        select coalesce(sum(units), 0)::int
          from public.usage_events
         where user_id = $1 and kind = $2
           and created_at >= date_trunc('day', timezone('utc', now()))
        """,
        user_id,
        kind,
    )
    return int(value or 0)


async def used_month(connection: DBConnection, user_id: uuid.UUID, kind: UsageKind) -> int:
    value = await connection.fetchval(
        """
        select coalesce(sum(units), 0)::int
          from public.usage_events
         where user_id = $1 and kind = $2
           and created_at >= date_trunc('month', timezone('utc', now()))
        """,
        user_id,
        kind,
    )
    return int(value or 0)


async def assert_quota(
    connection: DBConnection,
    *,
    user_id: uuid.UUID,
    plan: Plan,
    kind: UsageKind,
    units: int,
    settings: Settings,
) -> None:
    """Raises ``quota_exceeded`` when adding ``units`` would breach daily or monthly caps."""
    if units <= 0:
        return
    daily, monthly = limits_for(settings, plan, kind)
    day_used = await used_today(connection, user_id, kind)
    month_used = await used_month(connection, user_id, kind)
    if day_used + units > daily:
        raise APIError(429, ErrorCode.QUOTA_EXCEEDED, _message(kind, period="today"), retryable=False)
    if month_used + units > monthly:
        raise APIError(429, ErrorCode.QUOTA_EXCEEDED, _message(kind, period="this month"), retryable=False)


async def record_usage(
    connection: DBConnection,
    *,
    user_id: uuid.UUID,
    kind: UsageKind,
    outfit_id: uuid.UUID | None,
    units: int,
) -> None:
    if units <= 0:
        return
    await connection.execute(
        """
        insert into public.usage_events (user_id, kind, outfit_id, units)
        values ($1, $2, $3, $4)
        """,
        user_id,
        kind,
        outfit_id,
        units,
    )


def _message(kind: UsageKind, *, period: str) -> str:
    if kind == "look_render":
        return f"You've reached your styled-look limit for {period}. Try again later or unlock Grymode."
    return f"You've reached your try-on limit for {period}. Try again later or unlock Grymode."
