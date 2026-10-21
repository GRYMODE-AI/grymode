import asyncio
import logging
import time
import uuid
from dataclasses import dataclass
from typing import Any

import httpx
import jwt
from jwt import PyJWK, PyJWKSet

from app.errors import service_unavailable, unauthenticated

logger = logging.getLogger("grymode.auth")

# Supabase signs user tokens with asymmetric keys published at the JWKS endpoint.
# Symmetric algorithms are refused so a leaked anon/publishable key can never forge a token.
ALLOWED_ALGORITHMS = ("ES256", "RS256")
_MIN_REFRESH_INTERVAL_SECONDS = 30.0
_LEEWAY_SECONDS = 30


@dataclass(frozen=True, slots=True)
class AuthenticatedUser:
    id: uuid.UUID
    email: str | None
    claims: dict[str, Any]


class TokenVerifier:
    def __init__(
        self,
        *,
        jwks_url: str,
        issuer: str,
        audience: str,
        http: httpx.AsyncClient,
        cache_seconds: int = 600,
        clock: Any = time.monotonic,
    ) -> None:
        self._jwks_url = jwks_url
        self._issuer = issuer
        self._audience = audience
        self._http = http
        self._cache_seconds = cache_seconds
        self._clock = clock
        self._keys: dict[str, PyJWK] = {}
        self._fetched_at: float | None = None
        self._attempted_at: float | None = None
        self._lock = asyncio.Lock()

    async def verify(self, token: str) -> AuthenticatedUser:
        try:
            header = jwt.get_unverified_header(token)
        except jwt.InvalidTokenError as exc:
            raise unauthenticated() from exc

        algorithm = header.get("alg")
        key_id = header.get("kid")
        if algorithm not in ALLOWED_ALGORITHMS or not isinstance(key_id, str):
            raise unauthenticated()

        key = await self._key_for(key_id)
        if key is None:
            raise unauthenticated()

        try:
            claims: dict[str, Any] = jwt.decode(
                token,
                key=key,
                algorithms=[algorithm],
                audience=self._audience,
                issuer=self._issuer,
                leeway=_LEEWAY_SECONDS,
                options={"require": ["exp", "iat", "sub", "aud", "iss", "role"]},
            )
        except jwt.ExpiredSignatureError as exc:
            raise unauthenticated("Your session has expired. Sign in again.") from exc
        except jwt.InvalidTokenError as exc:
            raise unauthenticated() from exc

        if claims.get("role") != "authenticated" or claims.get("is_anonymous") is True:
            raise unauthenticated()
        try:
            user_id = uuid.UUID(str(claims["sub"]))
        except ValueError as exc:
            raise unauthenticated() from exc

        email = claims.get("email")
        return AuthenticatedUser(id=user_id, email=email if isinstance(email, str) and email else None, claims=claims)

    async def _key_for(self, key_id: str) -> PyJWK | None:
        if self._cache_is_fresh() and key_id in self._keys:
            return self._keys[key_id]
        async with self._lock:
            if self._cache_is_fresh() and key_id in self._keys:
                return self._keys[key_id]
            # Unknown key IDs trigger a refetch (key rotation), throttled so garbage tokens
            # can't turn into a flood of JWKS requests.
            if self._attempted_at is None or self._clock() - self._attempted_at >= _MIN_REFRESH_INTERVAL_SECONDS:
                await self._refresh()
            return self._keys.get(key_id)

    def _cache_is_fresh(self) -> bool:
        return self._fetched_at is not None and self._clock() - self._fetched_at < self._cache_seconds

    async def _refresh(self) -> None:
        self._attempted_at = self._clock()
        try:
            response = await self._http.get(self._jwks_url, timeout=5.0)
            response.raise_for_status()
            key_set = PyJWKSet.from_dict(response.json())
        except (httpx.HTTPError, ValueError, jwt.PyJWKSetError) as exc:
            logger.warning("jwks_refresh_failed", extra={"error_type": type(exc).__name__})
            if not self._keys:
                raise service_unavailable() from exc
            return
        self._keys = {
            key.key_id: key for key in key_set.keys if key.key_id and key.algorithm_name in ALLOWED_ALGORITHMS
        }
        self._fetched_at = self._clock()
