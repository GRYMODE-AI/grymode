from __future__ import annotations

import logging

from fastapi import APIRouter

from app import entitlements, subscriptions
from app.dependencies import CurrentUser, ServicesDep
from app.models import StrictModel
from app.outfit_models import EntitlementResponse
from app.storekit import parse_assn_notification, parse_transaction_jws

router = APIRouter(tags=["subscriptions"])
logger = logging.getLogger("grymode.subscriptions")


class SyncSubscriptionRequest(StrictModel):
    signed_transaction: str


class SyncSubscriptionResponse(StrictModel):
    entitlement: EntitlementResponse
    product_id: str
    status: str
    environment: str


class AppStoreNotificationRequest(StrictModel):
    signed_payload: str


class AppStoreNotificationResponse(StrictModel):
    received: bool = True


@router.post("/v1/subscriptions/sync", response_model=SyncSubscriptionResponse)
async def sync_subscription(
    body: SyncSubscriptionRequest, user: CurrentUser, services: ServicesDep
) -> SyncSubscriptionResponse:
    parsed = parse_transaction_jws(body.signed_transaction, settings=services.settings)
    async with services.database.as_service() as connection:
        result = await subscriptions.apply_parsed_transaction(connection, user_id=user.id, parsed=parsed)
        snap = await entitlements.entitlement_snapshot(connection, user.id)

    sub = result["subscription"]
    logger.info(
        "subscription_synced",
        extra={
            "user_id": str(user.id),
            "product_id": sub["product_id"],
            "status": sub["status"],
            "environment": sub["environment"],
            "plan": result["plan"],
        },
    )
    return SyncSubscriptionResponse(
        entitlement=EntitlementResponse(plan=snap["plan"], can_open_full_library=bool(snap["can_open_full_library"])),
        product_id=str(sub["product_id"]),
        status=str(sub["status"]),
        environment=str(sub["environment"]),
    )


@router.post("/v1/app-store/notifications", response_model=AppStoreNotificationResponse)
async def app_store_notifications(
    body: AppStoreNotificationRequest, services: ServicesDep
) -> AppStoreNotificationResponse:
    """App Store Server Notifications V2. Unauthenticated; authenticated by Apple's signed payload."""
    parsed_note = parse_assn_notification(body.signed_payload, settings=services.settings)
    transaction = parsed_note.get("transaction")
    if transaction is None:
        logger.info(
            "assn_ignored",
            extra={"notification_type": parsed_note.get("notification_type")},
        )
        return AppStoreNotificationResponse()

    async with services.database.as_service() as connection:
        owner = await connection.fetchval(
            """
            select user_id from public.subscriptions
             where original_transaction_id = $1
            """,
            transaction.original_transaction_id,
        )
        if owner is None:
            logger.warning(
                "assn_unknown_transaction",
                extra={"original_transaction_id": transaction.original_transaction_id},
            )
            # Acknowledge so Apple doesn't retry forever before the client has synced once.
            return AppStoreNotificationResponse()

        await subscriptions.apply_parsed_transaction(connection, user_id=owner, parsed=transaction)

    logger.info(
        "assn_applied",
        extra={
            "notification_type": parsed_note.get("notification_type"),
            "subtype": parsed_note.get("subtype"),
            "status": transaction.status,
        },
    )
    return AppStoreNotificationResponse()


@router.get("/v1/subscriptions/products")
async def list_product_ids(services: ServicesDep) -> dict[str, list[str]]:
    """Public product identifiers the client should load from StoreKit."""
    return {"product_ids": sorted(services.settings.allowed_product_ids)}
