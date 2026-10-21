import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from app.ai_outfit_composer import OpenAIOutfitComposer
from app.auth import TokenVerifier
from app.config import AIProvider, Settings
from app.db import Database
from app.dependencies import Services
from app.errors import install_error_handlers
from app.extraction import GarmentExtractor, LocalDraftExtractor, OpenAIGarmentExtractor
from app.logging import configure_logging
from app.middleware import RequestContextMiddleware
from app.openai_client import OpenAIImageClient, OpenAIResponsesClient
from app.outfit_generator import LocalOutfitGenerator, OutfitComposer
from app.ratelimit import SlidingWindowLimiter
from app.renders import RenderService
from app.routers import avatar, health, me, outfits, subscriptions, wardrobe
from app.storage import StorageClient
from app.supabase_admin import SupabaseAdmin

MAX_JSON_BODY_BYTES = 64 * 1024

logger = logging.getLogger("grymode.app")


def _ai_adapters(
    settings: Settings, database: Database, storage: StorageClient, http: httpx.AsyncClient
) -> tuple[GarmentExtractor, OutfitComposer, RenderService | None]:
    if settings.ai_provider is AIProvider.OPENAI and settings.ai_api_key is not None:
        client = OpenAIResponsesClient(
            api_key=settings.ai_api_key,
            base_url=str(settings.ai_base_url),
            http=http,
            timeout_seconds=settings.ai_timeout_seconds,
        )
        images = OpenAIImageClient(
            api_key=settings.ai_api_key,
            base_url=str(settings.ai_base_url),
            http=http,
            timeout_seconds=settings.ai_image_timeout_seconds,
        )
        logger.info(
            "ai_provider_configured",
            extra={
                "provider": settings.ai_provider.value,
                "vision_model": settings.ai_vision_model,
                "outfit_model": settings.ai_outfit_model,
                "image_model": settings.ai_image_model,
                "image_quality": settings.ai_image_quality,
            },
        )
        return (
            OpenAIGarmentExtractor(
                database=database,
                storage=storage,
                client=client,
                model=settings.ai_vision_model,
                max_items=settings.ai_max_garments_per_photo,
            ),
            OpenAIOutfitComposer(database=database, client=client, model=settings.ai_outfit_model),
            RenderService(
                database=database,
                storage=storage,
                images=images,
                settings=settings,
                model=settings.ai_image_model,
                quality=settings.ai_image_quality,
                concurrency=settings.ai_image_concurrency,
            ),
        )
    logger.info("ai_provider_configured", extra={"provider": AIProvider.LOCAL.value})
    return LocalDraftExtractor(database), LocalOutfitGenerator(database), None


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        async with httpx.AsyncClient(headers={"User-Agent": "grymode-api"}) as http:
            database = Database(
                settings.database_url.get_secret_value(),
                min_size=settings.database_pool_min_size,
                max_size=settings.database_pool_max_size,
            )
            await database.connect()
            storage = StorageClient(
                base_url=settings.supabase_base_url, secret_key=settings.supabase_secret_key, http=http
            )
            extractor, outfit_composer, renders = _ai_adapters(settings, database, storage, http)
            app.state.services = Services(
                settings=settings,
                database=database,
                verifier=TokenVerifier(
                    jwks_url=settings.jwks_url,
                    issuer=settings.jwt_issuer,
                    audience=settings.jwt_audience,
                    http=http,
                    cache_seconds=settings.jwks_cache_seconds,
                ),
                admin=SupabaseAdmin(
                    base_url=settings.supabase_base_url, secret_key=settings.supabase_secret_key, http=http
                ),
                storage=storage,
                extractor=extractor,
                outfit_composer=outfit_composer,
                request_limiter=SlidingWindowLimiter(limit=settings.rate_limit_requests_per_minute, window_seconds=60),
                deletion_limiter=SlidingWindowLimiter(
                    limit=settings.rate_limit_deletions_per_hour, window_seconds=3600
                ),
                renders=renders,
            )
            try:
                yield
            finally:
                await database.close()

    app = FastAPI(
        title="Grymode API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/docs" if settings.exposes_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if settings.exposes_docs else None,
    )
    install_error_handlers(app)
    app.add_middleware(RequestContextMiddleware, max_body_bytes=MAX_JSON_BODY_BYTES)
    app.include_router(health.router)
    app.include_router(me.router)
    app.include_router(avatar.router)
    app.include_router(wardrobe.router)
    app.include_router(outfits.router)
    app.include_router(subscriptions.router)
    return app
