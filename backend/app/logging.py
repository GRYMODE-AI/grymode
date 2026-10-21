import json
import logging
import sys
import traceback
from datetime import UTC, datetime
from typing import Any

from app.request_context import current_request_id

_RESERVED = frozenset(vars(logging.makeLogRecord({})).keys()) | {"message", "asctime"}


class JSONFormatter(logging.Formatter):
    """One JSON object per line, in the shape Cloud Logging understands.

    Only fields passed explicitly through ``extra=`` are emitted. Callers must never pass
    tokens, signed URLs, image data, email addresses, or request bodies.
    """

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "time": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "severity": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        request_id = current_request_id()
        if request_id:
            entry["request_id"] = request_id
        for key, value in vars(record).items():
            if key not in _RESERVED and not key.startswith("_"):
                entry[key] = value
        if record.exc_info and record.exc_info[0] is not None:
            exc_type, _, tb = record.exc_info
            entry["exception_type"] = f"{exc_type.__module__}.{exc_type.__qualname__}"
            # Frames only: exception messages can echo row values or request data.
            entry["stack"] = [f"{frame.filename}:{frame.lineno} {frame.name}" for frame in traceback.extract_tb(tb)][
                -12:
            ]
        return json.dumps(entry, default=str)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level.upper())
    for noisy in ("uvicorn.access", "httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
