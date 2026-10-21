from fastapi import APIRouter

from app.dependencies import ServicesDep
from app.models import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/v1/health", response_model=HealthResponse)
async def health(services: ServicesDep) -> HealthResponse:
    """Liveness check. Public, cheap, and independent of downstream services."""
    settings = services.settings
    return HealthResponse(status="ok", environment=settings.environment.value, version=settings.release)
