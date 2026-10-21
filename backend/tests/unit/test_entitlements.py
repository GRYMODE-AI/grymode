from app.entitlements import can_open_full_library, can_open_outfit


def test_free_user_opens_only_free_reveal() -> None:
    assert can_open_outfit(plan="free", is_free_reveal=True)
    assert not can_open_outfit(plan="free", is_free_reveal=False)
    assert not can_open_full_library("free")


def test_premium_user_opens_library() -> None:
    assert can_open_outfit(plan="premium", is_free_reveal=False)
    assert can_open_full_library("premium")
