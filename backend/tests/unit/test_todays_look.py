import uuid
from typing import Any

from app.outfits import occasion_filter_values, pick_todays_look


def _row(oid: str, *, free: bool = False, occasions: list[str] | None = None) -> dict[str, Any]:
    return {
        "id": uuid.UUID(oid),
        "is_free_reveal": free,
        "occasion_tags": occasions or [],
        "score": 1.0,
    }


def test_free_plan_prefers_free_reveal() -> None:
    user = uuid.uuid4()
    rows = [
        _row("11111111-1111-1111-1111-111111111111"),
        _row("22222222-2222-2222-2222-222222222222", free=True),
    ]
    picked = pick_todays_look(rows, user_id=user, day_key="2026-10-11", plan="free")
    assert picked is not None
    assert picked["is_free_reveal"] is True


def test_premium_rotates_deterministically() -> None:
    user = uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    rows = [
        _row("11111111-1111-1111-1111-111111111111"),
        _row("22222222-2222-2222-2222-222222222222"),
        _row("33333333-3333-3333-3333-333333333333"),
    ]
    a = pick_todays_look(rows, user_id=user, day_key="2026-10-11", plan="premium")
    b = pick_todays_look(rows, user_id=user, day_key="2026-10-11", plan="premium")
    assert a is not None
    assert b is not None
    assert a["id"] == b["id"]
    other_day = pick_todays_look(rows, user_id=user, day_key="2026-10-12", plan="premium")
    assert other_day is not None
    # Across many day keys the pick must cover more than one outfit.
    picks = set()
    for day in range(1, 31):
        picked = pick_todays_look(rows, user_id=user, day_key=f"2026-10-{day:02d}", plan="premium")
        assert picked is not None
        picks.add(picked["id"])
    assert len(picks) > 1


def test_empty_library_returns_none() -> None:
    assert pick_todays_look([], user_id=uuid.uuid4(), day_key="2026-10-11", plan="premium") is None


def test_occasion_filter_values_dedupe_preserve_order() -> None:
    rows = [
        _row("11111111-1111-1111-1111-111111111111", occasions=["work", "casual"]),
        _row("22222222-2222-2222-2222-222222222222", occasions=["casual", "evening"]),
    ]
    assert occasion_filter_values(rows) == ["work", "casual", "evening"]
