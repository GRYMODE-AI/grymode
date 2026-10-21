from enum import StrEnum
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.request_context import current_request_id


class ErrorCode(StrEnum):
    UNAUTHENTICATED = "unauthenticated"
    SESSION_REVOKED = "session_revoked"
    FORBIDDEN = "forbidden"
    NOT_FOUND = "not_found"
    METHOD_NOT_ALLOWED = "method_not_allowed"
    INVALID_REQUEST = "invalid_request"
    PAYLOAD_TOO_LARGE = "payload_too_large"
    RATE_LIMITED = "rate_limited"
    QUOTA_EXCEEDED = "quota_exceeded"
    SERVICE_UNAVAILABLE = "service_unavailable"
    INTERNAL_ERROR = "internal_error"


class APIError(Exception):
    """An error that is safe to show to the client.

    ``message`` must never contain internal details, tokens, or personal data.
    """

    def __init__(
        self,
        status_code: int,
        code: ErrorCode,
        message: str,
        *,
        retryable: bool = False,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.retryable = retryable
        self.headers = headers or {}


def error_body(code: ErrorCode, message: str, *, retryable: bool) -> dict[str, Any]:
    return {
        "code": code.value,
        "message": message,
        "request_id": current_request_id(),
        "retryable": retryable,
    }


def error_response(
    status_code: int,
    code: ErrorCode,
    message: str,
    *,
    retryable: bool = False,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content=error_body(code, message, retryable=retryable),
        headers=headers,
    )


def unauthenticated(message: str = "Sign in to continue.") -> APIError:
    return APIError(401, ErrorCode.UNAUTHENTICATED, message, headers={"WWW-Authenticate": "Bearer"})


def service_unavailable() -> APIError:
    return APIError(
        503,
        ErrorCode.SERVICE_UNAVAILABLE,
        "Grymode is temporarily unavailable. Please try again.",
        retryable=True,
    )


_HTTP_STATUS_CODES: dict[int, tuple[ErrorCode, str]] = {
    401: (ErrorCode.UNAUTHENTICATED, "Sign in to continue."),
    403: (ErrorCode.FORBIDDEN, "You don't have access to this."),
    404: (ErrorCode.NOT_FOUND, "Not found."),
    405: (ErrorCode.METHOD_NOT_ALLOWED, "This action isn't supported."),
    413: (ErrorCode.PAYLOAD_TOO_LARGE, "The request is too large."),
}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(APIError)
    async def _api_error(_: Request, exc: APIError) -> JSONResponse:
        return error_response(exc.status_code, exc.code, exc.message, retryable=exc.retryable, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        fields = sorted({".".join(str(part) for part in error["loc"][1:]) for error in exc.errors() if error["loc"]})
        message = "Some details are invalid."
        if fields:
            message = f"Some details are invalid: {', '.join(field for field in fields if field) or 'body'}."
        return error_response(422, ErrorCode.INVALID_REQUEST, message)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code, message = _HTTP_STATUS_CODES.get(
            exc.status_code, (ErrorCode.INVALID_REQUEST, "The request couldn't be completed.")
        )
        return error_response(exc.status_code, code, message, headers=getattr(exc, "headers", None))
