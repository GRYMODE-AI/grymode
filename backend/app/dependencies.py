from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth import AuthenticatedUser, TokenVerifier
from app.config import Settings
from app.db import Database
from app.errors import unauthenticated
from app.extraction import GarmentExtractor
from app.outfit_generator import OutfitComposer
from app.ratelimit import SlidingWindowLimiter
from app.renders import RenderService
from app.storage import StorageClient
from app.supabase_admin import SupabaseAdmin


@dataclass(slots=True)
class Services:
    settings: Settings
    database: Database
    verifier: TokenVerifier
    admin: SupabaseAdmin
    storage: StorageClient
    extractor: GarmentExtractor
    outfit_composer: OutfitComposer
    request_limiter: SlidingWindowLimiter
    deletion_limiter: SlidingWindowLimiter
    # None when no image provider is configured: looks show garment photos, try-on stays 2D.
    renders: RenderService | None = None


def get_services(request: Request) -> Services:
    services: Services = request.app.state.services
    return services


_bearer = HTTPBearer(auto_error=False)


async def get_current_user(
    services: Annotated[Services, Depends(get_services)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        raise unauthenticated()
    user = await services.verifier.verify(credentials.credentials)
    services.request_limiter.check(str(user.id))
    return user


ServicesDep = Annotated[Services, Depends(get_services)]
CurrentUser = Annotated[AuthenticatedUser, Depends(get_current_user)]
