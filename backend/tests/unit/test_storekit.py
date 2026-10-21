import base64
import json
import time
from typing import Any

import pytest

from app.config import Environment, Settings
from app.errors import APIError
from app.storekit import parse_transaction_jws


def _jws(payload: dict[str, Any]) -> str:
    header = base64.urlsafe_b64encode(json.dumps({"alg": "none"}).encode()).decode().rstrip("=")
    body = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"{header}.{body}.sig"


def _settings(**kwargs: object) -> Settings:
    base: dict[str, object] = {
        "environment": Environment.DEVELOPMENT,
        "supabase_url": "http://127.0.0.1:54321",
        "supabase_secret_key": "test-secret",
        "database_url": "postgresql://u:p@localhost/db",
        "ios_bundle_id": "com.grymode.stylist",
        "storekit_product_ids": "com.grymode.stylist.premium.monthly,com.grymode.stylist.premium.yearly",
        "ai_provider": "local",
    }
    base.update(kwargs)
    return Settings(**base)  # type: ignore[arg-type]


def test_parse_active_xcode_transaction() -> None:
    now = int(time.time() * 1000)
    jws = _jws(
        {
            "bundleId": "com.grymode.stylist",
            "productId": "com.grymode.stylist.premium.monthly",
            "originalTransactionId": "1001",
            "transactionId": "1002",
            "environment": "Xcode",
            "purchaseDate": now,
            "expiresDate": now + 86_400_000,
        }
    )
    parsed = parse_transaction_jws(jws, settings=_settings())
    assert parsed.status == "active"
    assert parsed.product_id.endswith(".monthly")


def test_reject_wrong_bundle() -> None:
    jws = _jws(
        {
            "bundleId": "com.other.app",
            "productId": "com.grymode.stylist.premium.monthly",
            "originalTransactionId": "1",
            "transactionId": "1",
            "environment": "Xcode",
        }
    )
    with pytest.raises(APIError):
        parse_transaction_jws(jws, settings=_settings())


def test_reject_xcode_outside_local() -> None:
    jws = _jws(
        {
            "bundleId": "com.grymode.stylist",
            "productId": "com.grymode.stylist.premium.monthly",
            "originalTransactionId": "1",
            "transactionId": "1",
            "environment": "Xcode",
        }
    )
    with pytest.raises(APIError):
        parse_transaction_jws(
            jws,
            settings=_settings(
                environment=Environment.PRODUCTION,
                supabase_url="https://example.supabase.co",
            ),
        )
