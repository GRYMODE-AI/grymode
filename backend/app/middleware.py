import json
import logging
import time

from starlette.datastructures import Headers, MutableHeaders
from starlette.exceptions import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.errors import ErrorCode, error_body
from app.request_context import accept_or_create_request_id, bind_request_id, reset_request_id

logger = logging.getLogger("grymode.request")

REQUEST_ID_HEADER = "X-Request-ID"


class RequestContextMiddleware:
    """Assigns a request ID, enforces a body size limit, logs one line per request, and
    turns any unhandled exception into the standard error contract.

    The access log records method, route path, status, and latency. It never records
    query strings, headers, or bodies.
    """

    def __init__(self, app: ASGIApp, *, max_body_bytes: int) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = Headers(scope=scope)
        request_id = accept_or_create_request_id(headers.get(REQUEST_ID_HEADER))
        token = bind_request_id(request_id)
        started = time.perf_counter()
        status_code = 500
        response_started = False

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code, response_started
            if message["type"] == "http.response.start":
                response_started = True
                status_code = message["status"]
                MutableHeaders(scope=message)[REQUEST_ID_HEADER] = request_id
            await send(message)

        try:
            declared_length = headers.get("content-length")
            if declared_length is not None and (
                not declared_length.isdigit() or int(declared_length) > self.max_body_bytes
            ):
                await self._send_error(
                    send_with_request_id, 413, ErrorCode.PAYLOAD_TOO_LARGE, "The request is too large."
                )
                return

            await self.app(scope, self._limited_receive(receive), send_with_request_id)
        except _BodyTooLargeError:
            if not response_started:
                await self._send_error(
                    send_with_request_id, 413, ErrorCode.PAYLOAD_TOO_LARGE, "The request is too large."
                )
        except Exception:
            logger.exception("unhandled_error", extra={"method": scope["method"], "path": _route_path(scope)})
            if not response_started:
                await self._send_error(
                    send_with_request_id,
                    500,
                    ErrorCode.INTERNAL_ERROR,
                    "Something went wrong on our side. Please try again.",
                    retryable=True,
                )
        finally:
            logger.info(
                "request",
                extra={
                    "method": scope["method"],
                    "path": _route_path(scope),
                    "status": status_code,
                    "latency_ms": round((time.perf_counter() - started) * 1000, 1),
                },
            )
            reset_request_id(token)

    def _limited_receive(self, receive: Receive) -> Receive:
        received = 0

        async def wrapped() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_body_bytes:
                    raise _BodyTooLargeError()
            return message

        return wrapped

    @staticmethod
    async def _send_error(send: Send, status: int, code: ErrorCode, message: str, *, retryable: bool = False) -> None:
        body = json.dumps(error_body(code, message, retryable=retryable)).encode()
        await send(
            {
                "type": "http.response.start",
                "status": status,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())],
            }
        )
        await send({"type": "http.response.body", "body": body})


class _BodyTooLargeError(HTTPException):
    """An HTTPException so FastAPI's body parser re-raises it rather than reporting a parse error."""

    def __init__(self) -> None:
        super().__init__(status_code=413)


def _route_path(scope: Scope) -> str:
    route = scope.get("route")
    path = getattr(route, "path", None)
    return path if isinstance(path, str) else "unmatched"
