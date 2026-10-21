"""StoreKit 2 / App Store Server Notification helpers.

Production must verify JWS signatures with Apple's root certificates (App Store Server Library).
Locally, Xcode StoreKit Testing produces well-formed JWS payloads we accept only in development/test
after structural checks (bundle id, product id, environment).
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Literal

from app.config import Settings
from app.errors import APIError, ErrorCode

logger = logging.getLogger("grymode.storekit")

EnvironmentName = Literal["Xcode", "Sandbox", "Production"]
SubscriptionStatus = Literal["active", "expired", "revoked", "billing_retry", "grace_period"]


@dataclass(frozen=True, slots=True)
class ParsedTransaction:
    original_transaction_id: str
    transaction_id: str
    product_id: str
    bundle_id: str
    environment: EnvironmentName
    purchased_at: datetime | None
    expires_at: datetime | None
    revoked_at: datetime | None
    jws_sha256: str
    status: SubscriptionStatus


def _b64url_json(segment: str) -> dict[str, Any]:
    padding = "=" * (-len(segment) % 4)
    raw = base64.urlsafe_b64decode(segment + padding)
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("JWS payload must be an object")
    return payload


def _ms_to_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(float(value) / 1000.0, tz=UTC)
    raise ValueError("timestamp must be milliseconds")


def decode_transaction_jws(jws: str) -> dict[str, Any]:
    parts = jws.strip().split(".")
    if len(parts) != 3:
        raise APIError(422, ErrorCode.INVALID_REQUEST, "The App Store receipt looks incomplete.", retryable=False)
    try:
        return _b64url_json(parts[1])
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise APIError(
            422, ErrorCode.INVALID_REQUEST, "The App Store receipt couldn't be read.", retryable=False
        ) from exc


def parse_transaction_payload(payload: dict[str, Any], *, jws: str, settings: Settings) -> ParsedTransaction:
    bundle_id = str(payload.get("bundleId") or "")
    product_id = str(payload.get("productId") or "")
    environment_raw = str(payload.get("environment") or "Sandbox")
    if environment_raw not in ("Xcode", "Sandbox", "Production"):
        # Older payloads may omit environment; treat unknown as Sandbox for structural parsing.
        environment_raw = "Sandbox"
    environment: EnvironmentName = environment_raw  # type: ignore[assignment]

    original = str(payload.get("originalTransactionId") or payload.get("transactionId") or "")
    transaction_id = str(payload.get("transactionId") or original)
    if not original or not transaction_id or not product_id or not bundle_id:
        raise APIError(422, ErrorCode.INVALID_REQUEST, "The App Store receipt is missing fields.", retryable=False)

    if bundle_id != settings.ios_bundle_id:
        raise APIError(422, ErrorCode.INVALID_REQUEST, "This purchase belongs to a different app.", retryable=False)
    if product_id not in settings.allowed_product_ids:
        raise APIError(422, ErrorCode.INVALID_REQUEST, "This product isn't offered by Grymode.", retryable=False)

    if environment == "Xcode" and not settings.accepts_local_storekit_testing:
        raise APIError(
            403,
            ErrorCode.FORBIDDEN,
            "Local StoreKit Testing purchases aren't accepted in this environment.",
            retryable=False,
        )
    if environment == "Production" and settings.environment.value == "development":
        # Still allow decode for reconciliation tests; production JWS should be signature-verified later.
        pass

    if settings.storekit_require_signed_jws and environment != "Xcode":
        # Placeholder until App Store Server Library credentials are configured.
        raise APIError(
            503,
            ErrorCode.SERVICE_UNAVAILABLE,
            "Subscription verification isn't configured for this environment yet.",
            retryable=True,
        )

    expires_at = _ms_to_dt(payload.get("expiresDate"))
    revoked_at = _ms_to_dt(payload.get("revocationDate"))
    purchased_at = _ms_to_dt(payload.get("purchaseDate"))
    now = datetime.now(tz=UTC)

    if revoked_at is not None:
        status: SubscriptionStatus = "revoked"
    elif expires_at is not None and expires_at <= now:
        status = "expired"
    else:
        status = "active"

    digest = hashlib.sha256(jws.encode("utf-8")).hexdigest()
    return ParsedTransaction(
        original_transaction_id=original,
        transaction_id=transaction_id,
        product_id=product_id,
        bundle_id=bundle_id,
        environment=environment,
        purchased_at=purchased_at,
        expires_at=expires_at,
        revoked_at=revoked_at,
        jws_sha256=digest,
        status=status,
    )


def parse_transaction_jws(jws: str, *, settings: Settings) -> ParsedTransaction:
    payload = decode_transaction_jws(jws)
    return parse_transaction_payload(payload, jws=jws, settings=settings)


def parse_assn_notification(signed_payload: str, *, settings: Settings) -> dict[str, Any]:
    """Extract notificationType + nested transaction info from an ASSN V2 signedPayload."""
    outer = decode_transaction_jws(signed_payload)
    data = outer.get("data") if isinstance(outer.get("data"), dict) else {}
    signed_transaction = data.get("signedTransactionInfo") if isinstance(data, dict) else None
    result: dict[str, Any] = {
        "notification_type": outer.get("notificationType"),
        "subtype": outer.get("subtype"),
        "transaction": None,
    }
    if isinstance(signed_transaction, str) and signed_transaction:
        try:
            result["transaction"] = parse_transaction_jws(signed_transaction, settings=settings)
        except APIError:
            logger.warning("assn_transaction_unreadable", extra={"notification_type": result["notification_type"]})
    return result
