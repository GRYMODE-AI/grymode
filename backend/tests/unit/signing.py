import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Any

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import ec

ISSUER = "http://supabase.test/auth/v1"
JWKS_URL = f"{ISSUER}/.well-known/jwks.json"


@dataclass
class SigningKey:
    """A locally generated ES256 key that stands in for a Supabase project signing key."""

    kid: str = field(default_factory=lambda: str(uuid.uuid4()))
    private_key: ec.EllipticCurvePrivateKey = field(default_factory=lambda: ec.generate_private_key(ec.SECP256R1()))

    def public_jwk(self) -> dict[str, Any]:
        jwk: dict[str, Any] = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(self.private_key.public_key()))
        return jwk | {"kid": self.kid, "alg": "ES256", "use": "sig"}

    def token(self, *, overrides: dict[str, Any] | None = None, omit: tuple[str, ...] = ()) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "sub": str(uuid.uuid4()),
            "aud": "authenticated",
            "iss": ISSUER,
            "role": "authenticated",
            "email": "person@example.com",
            "iat": now,
            "exp": now + 3600,
            "is_anonymous": False,
        }
        claims.update(overrides or {})
        for key in omit:
            claims.pop(key, None)
        return jwt.encode(claims, self.private_key, algorithm="ES256", headers={"kid": self.kid})


class JWKSServer:
    """Serves a mutable key set through httpx.MockTransport and counts fetches."""

    def __init__(self, *keys: SigningKey) -> None:
        self.keys = list(keys)
        self.fetches = 0
        self.fail = False

    def handler(self, request: httpx.Request) -> httpx.Response:
        if str(request.url) != JWKS_URL:
            return httpx.Response(404)
        self.fetches += 1
        if self.fail:
            return httpx.Response(503)
        return httpx.Response(200, json={"keys": [key.public_jwk() for key in self.keys]})

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=httpx.MockTransport(self.handler))
