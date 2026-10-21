import pytest

from app.errors import APIError
from app.ratelimit import SlidingWindowLimiter


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def test_allows_up_to_the_limit_then_blocks() -> None:
    limiter = SlidingWindowLimiter(limit=2, window_seconds=60, clock=FakeClock())
    limiter.check("a")
    limiter.check("a")

    with pytest.raises(APIError) as caught:
        limiter.check("a")

    assert caught.value.status_code == 429
    assert caught.value.headers["Retry-After"] == "60"


def test_window_slides() -> None:
    clock = FakeClock()
    limiter = SlidingWindowLimiter(limit=2, window_seconds=60, clock=clock)
    limiter.check("a")
    clock.now = 30
    limiter.check("a")
    clock.now = 60

    limiter.check("a")

    with pytest.raises(APIError) as caught:
        limiter.check("a")
    assert caught.value.headers["Retry-After"] == "30"


def test_keys_are_independent() -> None:
    limiter = SlidingWindowLimiter(limit=1, window_seconds=60, clock=FakeClock())
    limiter.check("a")

    limiter.check("b")


def test_blocked_attempts_do_not_extend_the_window() -> None:
    clock = FakeClock()
    limiter = SlidingWindowLimiter(limit=1, window_seconds=60, clock=clock)
    limiter.check("a")
    for second in range(1, 60):
        clock.now = second
        with pytest.raises(APIError):
            limiter.check("a")
    clock.now = 60

    limiter.check("a")
