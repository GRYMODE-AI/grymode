import pytest
from pydantic import SecretStr, ValidationError

from app.config import Environment, Settings
from app.errors import APIError, ErrorCode
from app.usage import limits_for


def _settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "environment": Environment.TEST,
        "supabase_url": "http://supabase.test",
        "supabase_secret_key": SecretStr("unit-test-secret"),
        "database_url": SecretStr("postgresql://unused@127.0.0.1:1/unused"),
        "ai_provider": "local",
    }
    values.update(overrides)
    return Settings.model_validate(values)


def test_auto_render_after_generation_defaults_off() -> None:
    assert _settings().ai_render_looks_after_generation is False


def test_quota_limits_are_higher_for_premium() -> None:
    settings = _settings()
    free_look = limits_for(settings, "free", "look_render")
    premium_look = limits_for(settings, "premium", "look_render")
    free_try = limits_for(settings, "free", "try_on")
    premium_try = limits_for(settings, "premium", "try_on")
    assert free_look[0] < premium_look[0]
    assert free_look[1] < premium_look[1]
    assert free_try[0] < premium_try[0]
    assert free_try[1] < premium_try[1]


def test_quota_exceeded_error_code_exists() -> None:
    err = APIError(429, ErrorCode.QUOTA_EXCEEDED, "limit", retryable=False)
    assert err.code == ErrorCode.QUOTA_EXCEEDED
    assert err.status_code == 429


def test_openai_still_requires_key() -> None:
    with pytest.raises(ValidationError):
        _settings(ai_provider="openai", ai_api_key=None)
