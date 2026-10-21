import time
from collections.abc import AsyncIterator

import httpx
import jwt
import pytest

from app.auth import TokenVerifier
from app.errors import APIError, ErrorCode
from tests.unit.signing import ISSUER, JWKS_URL, JWKSServer, SigningKey


class FakeClock:
    def __init__(self) -> None:
        self.now = 1_000.0

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def key() -> SigningKey:
    return SigningKey()


@pytest.fixture
def server(key: SigningKey) -> JWKSServer:
    return JWKSServer(key)


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock()


@pytest.fixture
async def http(server: JWKSServer) -> AsyncIterator[httpx.AsyncClient]:
    async with server.client() as client:
        yield client


@pytest.fixture
def verifier(http: httpx.AsyncClient, clock: FakeClock) -> TokenVerifier:
    return TokenVerifier(
        jwks_url=JWKS_URL, issuer=ISSUER, audience="authenticated", http=http, cache_seconds=600, clock=clock
    )


async def expect_error(verifier: TokenVerifier, token: str) -> APIError:
    with pytest.raises(APIError) as caught:
        await verifier.verify(token)
    return caught.value


async def test_accepts_a_valid_token(verifier: TokenVerifier, key: SigningKey) -> None:
    token = key.token(overrides={"sub": "6f1c3e9a-0000-4000-8000-000000000001"})

    user = await verifier.verify(token)

    assert str(user.id) == "6f1c3e9a-0000-4000-8000-000000000001"
    assert user.email == "person@example.com"
    assert user.claims["role"] == "authenticated"


@pytest.mark.parametrize(
    ("overrides", "omit"),
    [
        ({"aud": "someone-else"}, ()),
        ({"iss": "https://evil.example/auth/v1"}, ()),
        ({"role": "anon"}, ()),
        ({"role": "service_role"}, ()),
        ({"is_anonymous": True}, ()),
        ({"sub": "not-a-uuid"}, ()),
        ({}, ("sub",)),
        ({}, ("exp",)),
        ({}, ("role",)),
    ],
)
async def test_rejects_tokens_with_bad_claims(
    verifier: TokenVerifier, key: SigningKey, overrides: dict[str, object], omit: tuple[str, ...]
) -> None:
    error = await expect_error(verifier, key.token(overrides=overrides, omit=omit))

    assert error.status_code == 401
    assert error.code is ErrorCode.UNAUTHENTICATED


async def test_rejects_expired_tokens_with_a_specific_message(verifier: TokenVerifier, key: SigningKey) -> None:
    past = int(time.time()) - 7200
    error = await expect_error(verifier, key.token(overrides={"iat": past, "exp": past + 3600}))

    assert error.status_code == 401
    assert "expired" in error.message


async def test_rejects_symmetric_tokens_even_with_matching_claims(verifier: TokenVerifier) -> None:
    forged = jwt.encode(
        {"sub": "6f1c3e9a-0000-4000-8000-000000000001", "aud": "authenticated", "iss": ISSUER, "role": "authenticated"},
        "publishable-key-or-any-guess-at-a-shared-secret",
        algorithm="HS256",
        headers={"kid": "whatever"},
    )

    error = await expect_error(verifier, forged)

    assert error.status_code == 401


async def test_rejects_tokens_signed_by_an_unknown_key(verifier: TokenVerifier) -> None:
    error = await expect_error(verifier, SigningKey().token())

    assert error.status_code == 401


async def test_rejects_a_tampered_payload(verifier: TokenVerifier, key: SigningKey) -> None:
    header, payload, signature = key.token().split(".")
    other_payload = key.token(overrides={"sub": "6f1c3e9a-0000-4000-8000-000000000002"}).split(".")[1]

    error = await expect_error(verifier, f"{header}.{other_payload}.{signature}")

    assert error.status_code == 401
    assert payload != other_payload


@pytest.mark.parametrize("token", ["", "not-a-jwt", "a.b.c", "Bearer x.y.z"])
async def test_rejects_garbage(verifier: TokenVerifier, token: str) -> None:
    error = await expect_error(verifier, token)

    assert error.status_code == 401


async def test_caches_keys_between_requests(verifier: TokenVerifier, key: SigningKey, server: JWKSServer) -> None:
    for _ in range(5):
        await verifier.verify(key.token())

    assert server.fetches == 1


async def test_refetches_keys_after_rotation(
    verifier: TokenVerifier, key: SigningKey, server: JWKSServer, clock: FakeClock
) -> None:
    await verifier.verify(key.token())
    rotated = SigningKey()
    server.keys.append(rotated)
    clock.now += 31

    await verifier.verify(rotated.token())

    assert server.fetches == 2


async def test_throttles_refetches_for_unknown_key_ids(
    verifier: TokenVerifier, key: SigningKey, server: JWKSServer
) -> None:
    await verifier.verify(key.token())

    for _ in range(10):
        await expect_error(verifier, SigningKey().token())

    assert server.fetches == 1


async def test_reports_unavailable_when_keys_cannot_be_loaded(verifier: TokenVerifier, server: JWKSServer) -> None:
    server.fail = True

    error = await expect_error(verifier, SigningKey().token())

    assert error.status_code == 503
    assert error.retryable is True


async def test_keeps_cached_keys_when_a_refresh_fails(
    verifier: TokenVerifier, key: SigningKey, server: JWKSServer, clock: FakeClock
) -> None:
    await verifier.verify(key.token())
    server.fail = True
    clock.now += 601

    user = await verifier.verify(key.token())

    assert user.email == "person@example.com"
    assert server.fetches == 2
