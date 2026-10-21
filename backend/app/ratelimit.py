import math
import time
from collections import deque
from collections.abc import Callable

from app.errors import APIError, ErrorCode


class SlidingWindowLimiter:
    """In-process sliding-window limiter keyed by user.

    Each Cloud Run instance enforces its own window, so the effective ceiling is the limit
    multiplied by the instance count. That is acceptable as abuse protection for cheap
    routes; expensive routes (uploads, generation) get durable per-user quotas in the
    database when they are built.
    """

    def __init__(self, *, limit: int, window_seconds: float, clock: Callable[[], float] = time.monotonic) -> None:
        self._limit = limit
        self._window = window_seconds
        self._clock = clock
        self._hits: dict[str, deque[float]] = {}

    def check(self, key: str) -> None:
        now = self._clock()
        hits = self._hits.setdefault(key, deque())
        while hits and now - hits[0] >= self._window:
            hits.popleft()
        if len(hits) >= self._limit:
            retry_after = max(1, math.ceil(self._window - (now - hits[0])))
            raise APIError(
                429,
                ErrorCode.RATE_LIMITED,
                "You're doing that too often. Please wait a moment and try again.",
                retryable=True,
                headers={"Retry-After": str(retry_after)},
            )
        hits.append(now)
        if len(self._hits) > 10_000:
            self._evict_idle(now)

    def _evict_idle(self, now: float) -> None:
        for key in [key for key, hits in self._hits.items() if not hits or now - hits[-1] >= self._window]:
            del self._hits[key]
