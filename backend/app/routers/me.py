import logging

from fastapi import APIRouter

from app import entitlements, profiles, wardrobe
from app.dependencies import CurrentUser, ServicesDep
from app.errors import APIError
from app.models import AccountDeletionResponse, ProfileResponse, UpdateProfileRequest, UpdateStyleProfileRequest
from app.outfit_models import EntitlementResponse

router = APIRouter(tags=["account"])
logger = logging.getLogger("grymode.account")

SUBSCRIPTION_NOTICE = (
    "Deleting your account does not cancel an App Store subscription. "
    "Manage or cancel it in Settings > your name > Subscriptions."
)


@router.get("/v1/me", response_model=ProfileResponse)
async def get_me(user: CurrentUser, services: ServicesDep) -> ProfileResponse:
    async with services.database.as_user(user.claims) as connection:
        return await profiles.fetch_profile(connection, user)


@router.get("/v1/me/entitlement", response_model=EntitlementResponse)
async def get_entitlement(user: CurrentUser, services: ServicesDep) -> EntitlementResponse:
    async with services.database.as_user(user.claims) as connection:
        snap = await entitlements.entitlement_snapshot(connection, user.id)
    return EntitlementResponse(plan=snap["plan"], can_open_full_library=bool(snap["can_open_full_library"]))


@router.patch("/v1/me", response_model=ProfileResponse)
async def update_me(body: UpdateProfileRequest, user: CurrentUser, services: ServicesDep) -> ProfileResponse:
    async with services.database.as_user(user.claims) as connection:
        return await profiles.update_display_name(connection, user, body.display_name)


@router.put("/v1/me/style-profile", response_model=ProfileResponse)
async def put_style_profile(
    body: UpdateStyleProfileRequest, user: CurrentUser, services: ServicesDep
) -> ProfileResponse:
    async with services.database.as_user(user.claims) as connection:
        return await profiles.update_style_profile(
            connection, user, body.style_profile, onboarding_completed=body.onboarding_completed
        )


@router.delete("/v1/me", response_model=AccountDeletionResponse)
async def delete_me(user: CurrentUser, services: ServicesDep) -> AccountDeletionResponse:
    """Permanently deletes the account and everything keyed to it.

    The privacy request row is opened first and only marked completed after the auth user
    is gone, so a failure part-way leaves a ``processing`` record and the call can be
    retried safely. Deleting the auth user revokes refresh tokens and cascades to all
    user-owned rows.
    """
    services.deletion_limiter.check(str(user.id))

    async with services.database.as_service() as connection:
        request_id = await profiles.open_deletion_request(connection, user.id)
        object_keys = await wardrobe.list_object_keys_for_user(connection, user.id)

    if object_keys:
        try:
            await services.storage.remove_objects(object_keys)
        except APIError:
            logger.warning("wardrobe_media_cleanup_incomplete", extra={"privacy_request_id": str(request_id)})

    await services.admin.delete_user(user.id)

    async with services.database.as_service() as connection:
        await profiles.complete_deletion_request(connection, request_id)

    logger.info("account_deleted", extra={"privacy_request_id": str(request_id)})
    return AccountDeletionResponse(status="completed", request_id=request_id, subscription_notice=SUBSCRIPTION_NOTICE)
