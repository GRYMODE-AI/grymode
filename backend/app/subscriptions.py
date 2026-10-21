"""Persist verified StoreKit transactions and refresh entitlements."""

from __future__ import annotations

import uuid
from typing import Any

from app.db import DBConnection
from app.entitlements import fetch_plan
from app.errors import service_unavailable
from app.storekit import ParsedTransaction

# Support/test grants. StoreKit sync never overwrites these rows.
COMPLIMENTARY_SOURCE = "complimentary"


async def upsert_subscription(
    connection: DBConnection, *, user_id: uuid.UUID, parsed: ParsedTransaction
) -> dict[str, Any]:
    row = await connection.fetchrow(
        """
        insert into public.subscriptions (
            user_id, original_transaction_id, transaction_id, product_id, environment,
            status, purchased_at, expires_at, revoked_at, jws_sha256
        ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        on conflict (original_transaction_id) do update set
            user_id = excluded.user_id,
            transaction_id = excluded.transaction_id,
            product_id = excluded.product_id,
            environment = excluded.environment,
            status = excluded.status,
            purchased_at = excluded.purchased_at,
            expires_at = excluded.expires_at,
            revoked_at = excluded.revoked_at,
            jws_sha256 = excluded.jws_sha256,
            updated_at = now()
        returning id, user_id, original_transaction_id, product_id, status, expires_at, environment
        """,
        user_id,
        parsed.original_transaction_id,
        parsed.transaction_id,
        parsed.product_id,
        parsed.environment,
        parsed.status,
        parsed.purchased_at,
        parsed.expires_at,
        parsed.revoked_at,
        parsed.jws_sha256,
    )
    if row is None:
        raise service_unavailable()
    return dict(row)


async def refresh_entitlement_from_subscriptions(connection: DBConnection, user_id: uuid.UUID) -> str:
    """Set entitlements.plan from the best live subscription. Returns plan name."""
    live = await connection.fetchrow(
        """
        select expires_at
          from public.subscriptions
         where user_id = $1
           and status in ('active', 'billing_retry', 'grace_period')
           and (expires_at is null or expires_at > now())
           and revoked_at is null
         order by expires_at desc nulls first
         limit 1
        """,
        user_id,
    )
    if live is None:
        await connection.execute(
            """
            insert into public.entitlements (user_id, plan, source, expires_at)
            values ($1, 'free', 'subscription_sync', null)
            on conflict (user_id) do update set
                plan = 'free',
                source = 'subscription_sync',
                expires_at = null,
                updated_at = now()
             where public.entitlements.source <> $2
            """,
            user_id,
            COMPLIMENTARY_SOURCE,
        )
        return await fetch_plan(connection, user_id)

    await connection.execute(
        """
        insert into public.entitlements (user_id, plan, source, expires_at)
        values ($1, 'premium', 'subscription_sync', $2)
        on conflict (user_id) do update set
            plan = 'premium',
            source = 'subscription_sync',
            expires_at = excluded.expires_at,
            updated_at = now()
         where public.entitlements.source <> $3
        """,
        user_id,
        live["expires_at"],
        COMPLIMENTARY_SOURCE,
    )
    return "premium"


async def apply_parsed_transaction(
    connection: DBConnection, *, user_id: uuid.UUID, parsed: ParsedTransaction
) -> dict[str, Any]:
    subscription = await upsert_subscription(connection, user_id=user_id, parsed=parsed)
    plan = await refresh_entitlement_from_subscriptions(connection, user_id)
    return {"subscription": subscription, "plan": plan}
