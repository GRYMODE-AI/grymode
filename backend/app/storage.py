"""Supabase Storage helpers. Issues short-lived signed URLs; never returns permanent public URLs."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any
from urllib.parse import quote

import httpx
from pydantic import SecretStr

from app.errors import APIError, ErrorCode, service_unavailable

logger = logging.getLogger("grymode.storage")

WARDROBE_BUCKET = "wardrobe"
UPLOAD_URL_TTL_SECONDS = 600
READ_URL_TTL_SECONDS = 3600


def with_media_version(url: str, version: datetime | str | int | None) -> str:
    """Append a stable ``v`` query so clients can cache by path+version across re-signed tokens.

    Face photos and try-on renders reuse fixed object keys; without ``v``, an in-memory
    path-only cache keeps serving the previous person's pixels after a replace.
    """
    if version is None or not url:
        return url
    if isinstance(version, datetime):
        stamp = str(int(version.timestamp()))
    else:
        stamp = str(version)
    if not stamp:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}v={stamp}"


def build_signed_upload_url(base_url: str, path: str, token: str) -> str:
    """Join a Storage sign response with the API base without duplicating `token`.

    Local Supabase already returns `url` with `?token=…`. Older shapes return a bare path
    plus a separate `token` field — append once in that case only.
    """
    if path.startswith("http"):
        url = path
    else:
        suffix = path if path.startswith("/") else f"/{path}"
        url = f"{base_url.rstrip('/')}/storage/v1{suffix}"
    if "token=" in url:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}token={token}"


def parse_batch_signed(base_url: str, payload: Any) -> dict[str, str]:
    signed: dict[str, str] = {}
    if not isinstance(payload, list):
        return signed
    for item in payload:
        if not isinstance(item, dict) or item.get("error"):
            continue
        path = item.get("path")
        url = item.get("signedURL") or item.get("signedUrl")
        if not isinstance(path, str) or not isinstance(url, str) or not url:
            continue
        signed[path] = (
            url if url.startswith("http") else f"{base_url}/storage/v1{url if url.startswith('/') else '/' + url}"
        )
    return signed


class StorageClient:
    def __init__(self, *, base_url: str, secret_key: SecretStr, http: httpx.AsyncClient) -> None:
        self._base_url = base_url.rstrip("/")
        self._secret_key = secret_key
        self._http = http

    def _headers(self) -> dict[str, str]:
        key = self._secret_key.get_secret_value()
        headers = {"apikey": key, "Content-Type": "application/json"}
        if key.count(".") == 2:
            headers["Authorization"] = f"Bearer {key}"
        else:
            headers["Authorization"] = f"Bearer {key}"
        return headers

    async def create_signed_upload_url(self, object_key: str) -> str:
        """Returns a URL the client can PUT the file body to (includes the token)."""
        encoded = quote(object_key, safe="/")
        try:
            response = await self._http.post(
                f"{self._base_url}/storage/v1/object/upload/sign/{WARDROBE_BUCKET}/{encoded}",
                headers=self._headers(),
                json={"expiresIn": UPLOAD_URL_TTL_SECONDS},
                timeout=15.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc

        if not response.is_success:
            logger.error("signed_upload_failed", extra={"status": response.status_code})
            raise service_unavailable()

        payload: dict[str, Any] = response.json()
        token = payload.get("token")
        path = payload.get("url") or payload.get("signedURL") or payload.get("signedUrl")
        if not token or not isinstance(path, str):
            logger.error("signed_upload_malformed")
            raise service_unavailable()
        return build_signed_upload_url(self._base_url, path, token)

    async def create_signed_read_url(self, object_key: str, *, expires_in: int = READ_URL_TTL_SECONDS) -> str:
        encoded = quote(object_key, safe="/")
        try:
            response = await self._http.post(
                f"{self._base_url}/storage/v1/object/sign/{WARDROBE_BUCKET}/{encoded}",
                headers=self._headers(),
                json={"expiresIn": expires_in},
                timeout=15.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc

        if not response.is_success:
            logger.error("signed_read_failed", extra={"status": response.status_code})
            raise service_unavailable()

        payload: dict[str, Any] = response.json()
        signed = payload.get("signedURL") or payload.get("signedUrl") or payload.get("url")
        if not isinstance(signed, str) or not signed:
            logger.error("signed_read_malformed")
            raise service_unavailable()
        if signed.startswith("http"):
            return signed
        return f"{self._base_url}/storage/v1{signed if signed.startswith('/') else '/' + signed}"

    async def upload_object(self, object_key: str, data: bytes, content_type: str) -> None:
        """Server-side write (service key). Overwrites an existing object at the same key."""
        encoded = quote(object_key, safe="/")
        headers = self._headers() | {"Content-Type": content_type, "x-upsert": "true"}
        try:
            response = await self._http.post(
                f"{self._base_url}/storage/v1/object/{WARDROBE_BUCKET}/{encoded}",
                headers=headers,
                content=data,
                timeout=60.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc
        if not response.is_success:
            logger.error("storage_upload_failed", extra={"status": response.status_code})
            raise service_unavailable()

    async def create_signed_read_urls(
        self, object_keys: list[str], *, expires_in: int = READ_URL_TTL_SECONDS
    ) -> dict[str, str]:
        """Signs many objects in one request. Keys that fail to sign are omitted."""
        unique = list(dict.fromkeys(object_keys))
        if not unique:
            return {}
        try:
            response = await self._http.post(
                f"{self._base_url}/storage/v1/object/sign/{WARDROBE_BUCKET}",
                headers=self._headers(),
                json={"expiresIn": expires_in, "paths": unique},
                timeout=20.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc
        if not response.is_success:
            logger.error("signed_read_batch_failed", extra={"status": response.status_code})
            raise service_unavailable()
        return parse_batch_signed(self._base_url, response.json())

    async def download_object(self, object_key: str, *, max_bytes: int) -> tuple[bytes, str]:
        """Returns the object body and content type. Raises if missing or larger than ``max_bytes``."""
        encoded = quote(object_key, safe="/")
        headers = {k: v for k, v in self._headers().items() if k != "Content-Type"}
        try:
            response = await self._http.get(
                f"{self._base_url}/storage/v1/object/{WARDROBE_BUCKET}/{encoded}",
                headers=headers,
                timeout=30.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc
        if not response.is_success:
            logger.error("storage_download_failed", extra={"status": response.status_code})
            raise service_unavailable()
        if len(response.content) > max_bytes:
            logger.error("storage_download_too_large", extra={"bytes": len(response.content)})
            raise service_unavailable()
        content_type = response.headers.get("content-type", "application/octet-stream").split(";")[0].strip()
        return response.content, content_type

    async def object_exists(self, object_key: str) -> bool:
        encoded = quote(object_key, safe="/")
        try:
            response = await self._http.head(
                f"{self._base_url}/storage/v1/object/{WARDROBE_BUCKET}/{encoded}",
                headers=self._headers(),
                timeout=15.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc
        return response.is_success

    async def remove_objects(self, object_keys: list[str]) -> None:
        if not object_keys:
            return
        try:
            response = await self._http.request(
                "DELETE",
                f"{self._base_url}/storage/v1/object/{WARDROBE_BUCKET}",
                headers=self._headers(),
                json={"prefixes": object_keys},
                timeout=30.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("storage_delete_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc
        if response.status_code == 404 or response.is_success:
            return
        # Some deployments expect a plain list of paths.
        try:
            response = await self._http.request(
                "DELETE",
                f"{self._base_url}/storage/v1/object/{WARDROBE_BUCKET}",
                headers=self._headers(),
                json=object_keys,
                timeout=30.0,
            )
        except httpx.HTTPError as exc:
            raise service_unavailable() from exc
        if not (response.status_code == 404 or response.is_success):
            logger.error("storage_delete_failed", extra={"status": response.status_code})
            raise APIError(
                503,
                ErrorCode.SERVICE_UNAVAILABLE,
                "We couldn't finish clearing wardrobe media. Please try again.",
                retryable=True,
            )
