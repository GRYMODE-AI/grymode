from enum import StrEnum
from functools import cached_property
from typing import Literal

from pydantic import AnyHttpUrl, Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(StrEnum):
    DEVELOPMENT = "development"
    TEST = "test"
    STAGING = "staging"
    PRODUCTION = "production"


class AIProvider(StrEnum):
    LOCAL = "local"
    OPENAI = "openai"


class Settings(BaseSettings):
    """Runtime configuration.

    Values come from environment variables prefixed with ``GRYMODE_``. On Cloud Run the
    secret values are injected from Google Secret Manager; locally they come from a
    gitignored ``.env`` file. Nothing here has a usable default for a secret.
    """

    model_config = SettingsConfigDict(env_prefix="GRYMODE_", env_file=".env", extra="ignore")

    environment: Environment = Environment.DEVELOPMENT
    release: str = Field(default="local", max_length=64)
    log_level: str = "INFO"

    supabase_url: AnyHttpUrl
    supabase_secret_key: SecretStr
    database_url: SecretStr

    jwt_audience: str = "authenticated"
    jwks_cache_seconds: int = Field(default=600, ge=30, le=86_400)

    database_pool_min_size: int = Field(default=1, ge=0, le=50)
    database_pool_max_size: int = Field(default=10, ge=1, le=100)

    rate_limit_requests_per_minute: int = Field(default=120, ge=1)
    rate_limit_deletions_per_hour: int = Field(default=5, ge=1)

    # App Store / StoreKit. Product IDs must match App Store Connect and Products.storekit.
    ios_bundle_id: str = Field(default="com.grymode.stylist", min_length=3, max_length=128)
    storekit_product_ids: str = Field(default="com.grymode.stylist.premium.monthly,com.grymode.stylist.premium.yearly")
    # When false (staging/production default), only cryptographically verified App Store JWS is accepted.
    # Local Xcode StoreKit Testing payloads are accepted only in development/test.
    storekit_require_signed_jws: bool = False

    # AI provider. `local` keeps the rule-based adapters (no external calls); `openai` sends
    # wardrobe photos and structured wardrobe data to the OpenAI Responses API from the server only.
    ai_provider: AIProvider = AIProvider.LOCAL
    ai_api_key: SecretStr | None = None
    ai_base_url: AnyHttpUrl = AnyHttpUrl("https://api.openai.com/v1")
    ai_vision_model: str = Field(default="gpt-5.4-mini", min_length=1, max_length=80)
    ai_outfit_model: str = Field(default="gpt-6-astra", min_length=1, max_length=80)
    ai_timeout_seconds: float = Field(default=180.0, ge=10.0, le=600.0)
    ai_max_garments_per_photo: int = Field(default=4, ge=1, le=8)
    # Look visuals and personal try-on renders (Images API).
    ai_image_model: str = Field(default="gpt-image-2.5-sunburst", min_length=1, max_length=80)
    ai_image_quality: Literal["low", "medium", "high", "auto"] = "high"
    ai_image_timeout_seconds: float = Field(default=300.0, ge=30.0, le=900.0)
    ai_image_concurrency: int = Field(default=3, ge=1, le=8)
    # Cost control: never auto-bill look images after generate. Clients request via POST …/visual.
    ai_render_looks_after_generation: bool = False
    # Image usage quotas (new OpenAI image calls only; cache hits are free).
    ai_look_render_daily_free: int = Field(default=3, ge=0)
    ai_look_render_monthly_free: int = Field(default=10, ge=0)
    ai_look_render_daily_premium: int = Field(default=20, ge=0)
    ai_look_render_monthly_premium: int = Field(default=100, ge=0)
    ai_try_on_daily_free: int = Field(default=1, ge=0)
    ai_try_on_monthly_free: int = Field(default=3, ge=0)
    ai_try_on_daily_premium: int = Field(default=10, ge=0)
    ai_try_on_monthly_premium: int = Field(default=40, ge=0)

    @model_validator(mode="after")
    def _require_tls_outside_development(self) -> "Settings":
        if self.environment in (Environment.STAGING, Environment.PRODUCTION) and self.supabase_url.scheme != "https":
            raise ValueError("GRYMODE_SUPABASE_URL must use https outside local development")
        return self

    @model_validator(mode="after")
    def _require_ai_key_for_remote_provider(self) -> "Settings":
        if self.ai_provider is AIProvider.LOCAL:
            return self
        key = self.ai_api_key.get_secret_value().strip() if self.ai_api_key else ""
        if not key or "REPLACE" in key:
            raise ValueError("GRYMODE_AI_API_KEY must be set to a real key when GRYMODE_AI_PROVIDER is not 'local'")
        return self

    @property
    def allowed_product_ids(self) -> frozenset[str]:
        return frozenset(part.strip() for part in self.storekit_product_ids.split(",") if part.strip())

    @property
    def accepts_local_storekit_testing(self) -> bool:
        if self.environment in (Environment.DEVELOPMENT, Environment.TEST):
            return not self.storekit_require_signed_jws
        return False

    @cached_property
    def supabase_base_url(self) -> str:
        return str(self.supabase_url).rstrip("/")

    @cached_property
    def jwt_issuer(self) -> str:
        return f"{self.supabase_base_url}/auth/v1"

    @cached_property
    def jwks_url(self) -> str:
        return f"{self.jwt_issuer}/.well-known/jwks.json"

    @property
    def exposes_docs(self) -> bool:
        return self.environment in (Environment.DEVELOPMENT, Environment.TEST)
