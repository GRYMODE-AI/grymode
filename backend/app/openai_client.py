"""Minimal OpenAI clients: Responses API (structured JSON) and Images API (reference edits).

Server-side only. The API key never leaves the backend, prompts and outputs are never
logged, and responses are requested with ``store: false``.
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import json
import logging
from dataclasses import dataclass
from typing import Any

import httpx
from pydantic import SecretStr

logger = logging.getLogger("grymode.ai")

RETRYABLE_STATUS = frozenset({408, 409, 429, 500, 502, 503, 504})
MAX_ATTEMPTS = 3


class AIProviderError(RuntimeError):
    """The provider failed, refused, or returned output that does not match the schema."""

    def __init__(self, code: str, *, status: int | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.status = status


def image_data_url(data: bytes, content_type: str) -> str:
    return f"data:{content_type};base64,{base64.b64encode(data).decode('ascii')}"


def _output_text(payload: dict[str, Any]) -> str:
    for item in payload.get("output") or []:
        if item.get("type") != "message":
            continue
        for part in item.get("content") or []:
            kind = part.get("type")
            if kind == "refusal":
                raise AIProviderError("ai_refused")
            if kind == "output_text" and isinstance(part.get("text"), str):
                return str(part["text"])
    raise AIProviderError("ai_empty_output")


@dataclass(frozen=True, slots=True)
class ReferenceImage:
    data: bytes
    content_type: str


class OpenAIImageClient:
    """Images API edits: renders a new image conditioned on up to 16 reference images."""

    MAX_REFERENCES = 16

    def __init__(self, *, api_key: SecretStr, base_url: str, http: httpx.AsyncClient, timeout_seconds: float) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._http = http
        self._timeout = timeout_seconds

    async def edit(
        self,
        *,
        model: str,
        prompt: str,
        references: list[ReferenceImage],
        size: str,
        quality: str,
        purpose: str,
    ) -> bytes:
        if not references or len(references) > self.MAX_REFERENCES:
            raise AIProviderError("image_reference_count")
        files = [
            ("image[]", (f"ref-{index}.{_extension(ref.content_type)}", ref.data, ref.content_type))
            for index, ref in enumerate(references, start=1)
        ]
        data = {
            "model": model,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "output_format": "jpeg",
            "output_compression": "90",
        }
        headers = {"Authorization": f"Bearer {self._api_key.get_secret_value()}"}

        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                response = await self._http.post(
                    f"{self._base_url}/images/edits", headers=headers, data=data, files=files, timeout=self._timeout
                )
            except httpx.TimeoutException as exc:
                logger.warning("ai_image_timeout", extra={"purpose": purpose, "attempt": attempt, "model": model})
                if attempt == MAX_ATTEMPTS:
                    raise AIProviderError("ai_timeout") from exc
                await asyncio.sleep(2**attempt)
                continue
            except httpx.HTTPError as exc:
                logger.warning(
                    "ai_unreachable", extra={"purpose": purpose, "attempt": attempt, "error_type": type(exc).__name__}
                )
                if attempt == MAX_ATTEMPTS:
                    raise AIProviderError("ai_unreachable") from exc
                await asyncio.sleep(2**attempt)
                continue

            if response.status_code in RETRYABLE_STATUS and attempt < MAX_ATTEMPTS:
                logger.warning(
                    "ai_retryable_status",
                    extra={"purpose": purpose, "attempt": attempt, "status": response.status_code},
                )
                await asyncio.sleep(2**attempt)
                continue

            if not response.is_success:
                error: dict[str, Any] = {}
                with contextlib.suppress(ValueError):
                    error = response.json().get("error") or {}
                code = str(error.get("code") or "")
                logger.error(
                    "ai_image_failed",
                    extra={"purpose": purpose, "status": response.status_code, "error_code": code, "model": model},
                )
                if "moderation" in code or "safety" in code:
                    raise AIProviderError("image_blocked", status=response.status_code)
                raise AIProviderError("ai_request_failed", status=response.status_code)

            payload: dict[str, Any] = response.json()
            usage = payload.get("usage") or {}
            logger.info(
                "ai_image_response",
                extra={
                    "purpose": purpose,
                    "model": model,
                    "quality": quality,
                    "input_tokens": usage.get("input_tokens"),
                    "output_tokens": usage.get("output_tokens"),
                },
            )
            items = payload.get("data") or []
            encoded = items[0].get("b64_json") if items and isinstance(items[0], dict) else None
            if not isinstance(encoded, str) or not encoded:
                raise AIProviderError("ai_empty_output")
            try:
                return base64.b64decode(encoded)
            except ValueError as exc:
                raise AIProviderError("ai_invalid_image") from exc

        raise AIProviderError("ai_request_failed")


def _extension(content_type: str) -> str:
    return {"image/png": "png", "image/webp": "webp"}.get(content_type, "jpg")


class OpenAIResponsesClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        base_url: str,
        http: httpx.AsyncClient,
        timeout_seconds: float,
    ) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._http = http
        self._timeout = timeout_seconds

    async def structured(
        self,
        *,
        model: str,
        instructions: str,
        content: list[dict[str, Any]],
        schema_name: str,
        schema: dict[str, Any],
        purpose: str,
    ) -> dict[str, Any]:
        body = {
            "model": model,
            "instructions": instructions,
            "input": [{"role": "user", "content": content}],
            "text": {"format": {"type": "json_schema", "name": schema_name, "strict": True, "schema": schema}},
            "store": False,
        }
        headers = {
            "Authorization": f"Bearer {self._api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }

        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                response = await self._http.post(
                    f"{self._base_url}/responses", headers=headers, json=body, timeout=self._timeout
                )
            except httpx.TimeoutException as exc:
                logger.warning("ai_timeout", extra={"purpose": purpose, "attempt": attempt, "model": model})
                if attempt == MAX_ATTEMPTS:
                    raise AIProviderError("ai_timeout") from exc
                await asyncio.sleep(2**attempt)
                continue
            except httpx.HTTPError as exc:
                logger.warning(
                    "ai_unreachable",
                    extra={"purpose": purpose, "attempt": attempt, "error_type": type(exc).__name__},
                )
                if attempt == MAX_ATTEMPTS:
                    raise AIProviderError("ai_unreachable") from exc
                await asyncio.sleep(2**attempt)
                continue

            if response.status_code in RETRYABLE_STATUS and attempt < MAX_ATTEMPTS:
                logger.warning(
                    "ai_retryable_status",
                    extra={"purpose": purpose, "attempt": attempt, "status": response.status_code},
                )
                await asyncio.sleep(2**attempt)
                continue

            if not response.is_success:
                error_type = None
                with contextlib.suppress(ValueError):
                    error_type = (response.json().get("error") or {}).get("type")
                logger.error(
                    "ai_request_failed",
                    extra={
                        "purpose": purpose,
                        "status": response.status_code,
                        "error_type": error_type,
                        "model": model,
                    },
                )
                raise AIProviderError("ai_request_failed", status=response.status_code)

            payload: dict[str, Any] = response.json()
            if payload.get("status") == "incomplete":
                reason = (payload.get("incomplete_details") or {}).get("reason")
                logger.error("ai_incomplete", extra={"purpose": purpose, "reason": reason, "model": model})
                raise AIProviderError("ai_incomplete")

            usage = payload.get("usage") or {}
            logger.info(
                "ai_response",
                extra={
                    "purpose": purpose,
                    "model": model,
                    "input_tokens": usage.get("input_tokens"),
                    "output_tokens": usage.get("output_tokens"),
                },
            )
            text = _output_text(payload)
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError as exc:
                raise AIProviderError("ai_invalid_json") from exc
            if not isinstance(parsed, dict):
                raise AIProviderError("ai_invalid_json")
            return parsed

        raise AIProviderError("ai_request_failed")
