from collections.abc import AsyncIterator

import httpx
import pytest
from fastapi import FastAPI
from pydantic import SecretStr

from app.auth import TokenVerifier
from app.config import Environment, Settings
from app.db import Database
from app.dependencies import Services
from app.extraction import LocalDraftExtractor
from app.main import MAX_JSON_BODY_BYTES, create_app
from app.outfit_generator import LocalOutfitGenerator
from app.ratelimit import SlidingWindowLimiter
from app.storage import StorageClient
from app.supabase_admin import SupabaseAdmin
from tests.unit.signing import ISSUER, JWKS_URL, JWKSServer, SigningKey

ERROR_FIELDS = {"code", "message", "request_id", "retryable"}


def make_settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "environment": Environment.TEST,
        "supabase_url": "http://supabase.test",
        "supabase_secret_key": SecretStr("unit-test-secret"),
        "database_url": SecretStr("postgresql://unused@127.0.0.1:1/unused"),
        "log_level": "WARNING",
        "ai_provider": "local",
    }
    values.update(overrides)
    return Settings.model_validate(values)


@pytest.fixture
def key() -> SigningKey:
    return SigningKey()


@pytest.fixture
async def app(key: SigningKey) -> AsyncIterator[FastAPI]:
    settings = make_settings()
    application = create_app(settings)

    @application.get("/v1/test/boom")
    async def boom() -> None:
        raise RuntimeError("secret detail that must not leak")

    @application.post("/v1/test/echo")
    async def echo(body: dict[str, str]) -> dict[str, str]:
        return body

    async with JWKSServer(key).client() as http:
        database = Database(settings.database_url.get_secret_value(), min_size=0, max_size=1)
        application.state.services = Services(
            settings=settings,
            database=database,
            verifier=TokenVerifier(jwks_url=JWKS_URL, issuer=ISSUER, audience="authenticated", http=http),
            admin=SupabaseAdmin(
                base_url=settings.supabase_base_url, secret_key=settings.supabase_secret_key, http=http
            ),
            storage=StorageClient(
                base_url=settings.supabase_base_url, secret_key=settings.supabase_secret_key, http=http
            ),
            extractor=LocalDraftExtractor(database),
            outfit_composer=LocalOutfitGenerator(database),
            request_limiter=SlidingWindowLimiter(limit=3, window_seconds=60),
            deletion_limiter=SlidingWindowLimiter(limit=1, window_seconds=3600),
        )
        yield application


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://api.test") as http:
        yield http


async def test_health_is_public(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "environment": "test", "version": "local"}
    assert response.headers["x-request-id"]


@pytest.mark.parametrize(
    ("method", "path"),
    [("GET", "/v1/me"), ("PATCH", "/v1/me"), ("PUT", "/v1/me/style-profile"), ("DELETE", "/v1/me")],
)
async def test_account_routes_require_a_token(client: httpx.AsyncClient, method: str, path: str) -> None:
    response = await client.request(method, path)

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    body = response.json()
    assert set(body) == ERROR_FIELDS
    assert body["code"] == "unauthenticated"
    assert body["retryable"] is False
    assert body["request_id"] == response.headers["x-request-id"]


async def test_rejects_non_bearer_schemes(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/me", headers={"Authorization": "Basic dXNlcjpwYXNz"})

    assert response.status_code == 401


async def test_rejects_forged_tokens(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/me", headers={"Authorization": f"Bearer {SigningKey().token()}"})

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"


async def test_echoes_a_well_formed_client_request_id(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/health", headers={"X-Request-ID": "ios-3F2A9C1B-7E44"})

    assert response.headers["x-request-id"] == "ios-3F2A9C1B-7E44"


async def test_replaces_a_malformed_client_request_id(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/health", headers={"X-Request-ID": "<script>alert(1)</script>"})

    assert response.headers["x-request-id"] != "<script>alert(1)</script>"
    assert len(response.headers["x-request-id"]) == 36


async def test_unknown_routes_use_the_error_contract(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/nope")

    assert response.status_code == 404
    assert set(response.json()) == ERROR_FIELDS
    assert response.json()["code"] == "not_found"


async def test_unhandled_errors_are_safe(client: httpx.AsyncClient) -> None:
    response = await client.get("/v1/test/boom")

    assert response.status_code == 500
    body = response.json()
    assert set(body) == ERROR_FIELDS
    assert body["code"] == "internal_error"
    assert body["retryable"] is True
    assert "secret detail" not in response.text
    assert body["request_id"] == response.headers["x-request-id"]


async def test_validation_errors_name_fields_but_not_values(client: httpx.AsyncClient) -> None:
    response = await client.post("/v1/test/echo", json={"name": 12345678})

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "invalid_request"
    assert "name" in body["message"]
    assert "12345678" not in body["message"]


async def test_rejects_bodies_over_the_limit_by_content_length(client: httpx.AsyncClient) -> None:
    response = await client.post("/v1/test/echo", content=b"{" + b" " * MAX_JSON_BODY_BYTES + b"}")

    assert response.status_code == 413
    assert response.json()["code"] == "payload_too_large"


async def test_rejects_streamed_bodies_over_the_limit(client: httpx.AsyncClient) -> None:
    async def chunks() -> AsyncIterator[bytes]:
        for _ in range(MAX_JSON_BODY_BYTES // 1024 + 2):
            yield b" " * 1024

    response = await client.post("/v1/test/echo", content=chunks(), headers={"Content-Type": "application/json"})

    assert response.status_code == 413
    assert response.json()["code"] == "payload_too_large"


async def test_rate_limits_per_user(client: httpx.AsyncClient, key: SigningKey) -> None:
    # The fixture allows 3 authenticated requests per minute. An empty PATCH body fails
    # validation (422) after authentication, so no database is needed to exercise the limiter.
    alice = {"Authorization": f"Bearer {key.token()}"}
    bob = {"Authorization": f"Bearer {key.token()}"}

    statuses = [(await client.patch("/v1/me", headers=alice, json={})).status_code for _ in range(3)]
    limited = await client.patch("/v1/me", headers=alice, json={})
    other_user = await client.patch("/v1/me", headers=bob, json={})

    assert statuses == [422, 422, 422]
    assert limited.status_code == 429
    assert limited.json()["code"] == "rate_limited"
    assert limited.json()["retryable"] is True
    assert int(limited.headers["retry-after"]) >= 1
    assert other_user.status_code == 422


async def test_docs_are_hidden_in_production() -> None:
    application = create_app(make_settings(environment=Environment.PRODUCTION, supabase_url="https://x.supabase.co"))
    transport = httpx.ASGITransport(app=application)
    async with httpx.AsyncClient(transport=transport, base_url="http://api.test") as http:
        assert (await http.get("/docs")).status_code == 404
        assert (await http.get("/openapi.json")).status_code == 404


def test_production_requires_https_supabase() -> None:
    with pytest.raises(ValueError, match="https"):
        make_settings(environment=Environment.PRODUCTION, supabase_url="http://insecure.example")
