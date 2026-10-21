import re
import uuid
from contextvars import ContextVar, Token

_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)

_CLIENT_REQUEST_ID = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def accept_or_create_request_id(client_value: str | None) -> str:
    if client_value and _CLIENT_REQUEST_ID.fullmatch(client_value):
        return client_value
    return str(uuid.uuid4())


def current_request_id() -> str | None:
    return _request_id.get()


def bind_request_id(value: str) -> Token[str | None]:
    return _request_id.set(value)


def reset_request_id(token: Token[str | None]) -> None:
    _request_id.reset(token)
