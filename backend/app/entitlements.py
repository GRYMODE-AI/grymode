"""Authoritative access plan. Missing row = free."""

from __future__ import annotations

import uuid
from typing import Any, Literal

from app.db import DBConnection

Plan = Literal["free", "premium"]


async def fetch_plan(connection: DBConnection, user_id: uuid.UUID) -> Plan:
    row = await connection.fetchrow(
        """
        select plan, expires_at
          from public.entitlements
         where user_id = $1
        """,
        user_id,
    )
    if row is None:
        return "free"
    plan = str(row["plan"])
    if plan != "premium":
        return "free"
    expires_at = row["expires_at"]
    if expires_at is not None:
        # Compare in SQL would be cleaner; keep simple: fetchrow already returned the row.
        live = await connection.fetchval(
            """
            select true from public.entitlements
             where user_id = $1 and plan = 'premium'
               and (expires_at is null or expires_at > now())
            """,
            user_id,
        )
        return "premium" if live else "free"
    return "premium"


def can_open_full_library(plan: Plan) -> bool:
    return plan == "premium"


def can_open_outfit(*, plan: Plan, is_free_reveal: bool) -> bool:
    return is_free_reveal or plan == "premium"


async def entitlement_snapshot(connection: DBConnection, user_id: uuid.UUID) -> dict[str, Any]:
    plan = await fetch_plan(connection, user_id)
    return {
        "plan": plan,
        "can_open_full_library": can_open_full_library(plan),
    }
