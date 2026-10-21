import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from app.renders import (
    GARMENT_FIDELITY,
    STALE_IN_FLIGHT,
    garment_label,
    look_prompt,
    look_signature,
    needs_render,
    reference_plan,
    render_object_key,
    try_on_front_prompt,
    try_on_signature,
    try_on_view_prompt,
)
from app.routers.avatar import _session_status
from app.storage import parse_batch_signed


def _piece(position: int, key: str, category: str, slot: str, **extra: Any) -> dict[str, Any]:
    return {"position": position, "image_object_key": key, "category": category, "slot": slot, **extra}


NOW = datetime(2026, 10, 13, 12, 0, tzinfo=UTC)


def test_garment_label_prefers_subcategory_and_skips_plain_details() -> None:
    assert garment_label({"category": "tops", "subcategory": "oxford shirt", "primary_color": "white"}) == (
        "white oxford shirt"
    )
    assert garment_label({"category": "bottoms", "primary_color": "navy", "pattern": "solid"}) == "navy trousers"
    assert garment_label(
        {"category": "knitwear", "subcategory": "crewneck", "primary_color": "camel", "material": "merino"}
    ) == ("camel crewneck (merino)")


def test_reference_plan_dedupes_shared_photos_in_position_order() -> None:
    pieces = [
        _piece(2, "u/a.jpg", "shoes", "footwear"),
        _piece(0, "u/b.jpg", "tops", "primary"),
        _piece(1, "u/a.jpg", "bottoms", "bottom"),
    ]
    keys, paired = reference_plan(pieces)
    assert keys == ["u/b.jpg", "u/a.jpg"]
    assert [(p["category"], index) for p, index in paired] == [("tops", 0), ("bottoms", 1), ("shoes", 1)]


def test_look_prompt_lists_every_piece_and_flags_shared_photo() -> None:
    _, paired = reference_plan(
        [
            _piece(0, "u/top.jpg", "tops", "primary", subcategory="oxford shirt", primary_color="white"),
            _piece(1, "u/set.jpg", "bottoms", "bottom", subcategory="chinos", primary_color="beige"),
            _piece(2, "u/set.jpg", "shoes", "footwear", subcategory="loafers", primary_color="black"),
        ]
    )
    prompt = look_prompt(paired)
    assert "white oxford shirt — from Image 1" in prompt
    assert "beige chinos — from Image 2 (that photo shows several items" in prompt
    assert "black loafers" in prompt
    assert "ghost mannequin" in prompt
    assert GARMENT_FIDELITY in prompt


def test_look_prompt_never_invites_unlisted_items() -> None:
    _, paired = reference_plan(
        [
            _piece(0, "u/1.jpg", "knitwear", "primary", subcategory="crewneck", primary_color="camel"),
            _piece(1, "u/2.jpg", "bottoms", "bottom", primary_color="charcoal"),
            _piece(2, "u/3.jpg", "shoes", "footwear", subcategory="chelsea boots", primary_color="brown"),
        ]
    )
    prompt = look_prompt(paired)
    assert "Show ONLY these 3 items" in prompt
    assert "bag rests" not in prompt
    assert "outer layer is worn open" not in prompt

    _, with_bag = reference_plan(
        [
            _piece(0, "u/1.jpg", "tops", "primary"),
            _piece(1, "u/2.jpg", "bottoms", "bottom"),
            _piece(2, "u/3.jpg", "bags", "bag", subcategory="messenger bag"),
        ]
    )
    assert "the listed bag rests beside the legs" in look_prompt(with_bag)


def test_try_on_prompts_offset_images_after_face_and_front() -> None:
    _, paired = reference_plan([_piece(0, "u/top.jpg", "tops", "primary", primary_color="navy")])
    front = try_on_front_prompt(height_cm=180, body_build="slim", paired=paired)
    assert "180 cm tall with a slim, lean build" in front
    assert "Image 1 is a photo of the user's face" in front
    assert "from Image 2" in front

    back = try_on_view_prompt("back", paired=paired)
    assert "back view" in back
    assert "from Image 3" in back


def test_look_signature_includes_outfit_garment_set() -> None:
    assert look_signature("a|b|c").startswith("look-v3:")
    assert len(look_signature("a|b|c")) <= 128
    assert look_signature("a|b") != look_signature("a|c")


def test_try_on_signature_is_stable_for_face_and_outfit() -> None:
    base = {"face_object_key": "u/avatar/face.jpg", "height_cm": 180, "body_build": "slim", "updated_at": NOW}
    outfit = "g1|g2|g3"
    assert try_on_signature(base, outfit_signature=outfit) == try_on_signature(
        {**base}, outfit_signature=outfit
    )
    assert try_on_signature(base, outfit_signature=outfit).startswith("tryon-v4:")
    # Replacing the face at the same object key bumps updated_at and must miss cache.
    assert try_on_signature(base, outfit_signature=outfit) != try_on_signature(
        {**base, "updated_at": NOW + timedelta(days=1)}, outfit_signature=outfit
    )
    assert try_on_signature(base, outfit_signature=outfit) != try_on_signature(
        {**base, "height_cm": 181}, outfit_signature=outfit
    )
    assert try_on_signature(base, outfit_signature=outfit) != try_on_signature(base, outfit_signature="g1|g2|g9")


def test_needs_render_rules() -> None:
    sig = look_signature("tops|bottoms")

    def row(status: str, *, signature: str = sig, age: timedelta = timedelta()) -> dict[str, Any]:
        return {"status": status, "input_signature": signature, "updated_at": NOW - age}

    assert needs_render(None, signature=sig, now=NOW)
    assert needs_render(row("failed"), signature=sig, now=NOW)
    assert needs_render(row("succeeded", signature="old"), signature=sig, now=NOW)
    assert not needs_render(row("succeeded"), signature=sig, now=NOW)
    assert not needs_render(row("running", age=timedelta(minutes=1)), signature=sig, now=NOW)
    stale = STALE_IN_FLIGHT + timedelta(seconds=1)
    assert needs_render(row("pending", age=stale), signature=sig, now=NOW)


def test_render_object_key_is_user_scoped() -> None:
    user, outfit, render = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    assert render_object_key(user, outfit, render) == f"{user}/renders/{outfit}/{render}.jpg"


def test_session_status_aggregation() -> None:
    def rows(**statuses: str) -> list[dict[str, Any]]:
        return [{"view": view, "status": status} for view, status in statuses.items()]

    assert _session_status([]) == "idle"
    assert _session_status(rows(front="succeeded", side="running")) == "rendering"
    assert (
        _session_status(rows(front="succeeded", three_quarter="succeeded", side="succeeded", back="succeeded"))
        == "ready"
    )
    assert _session_status(rows(front="succeeded", three_quarter="failed", side="succeeded", back="failed")) == (
        "partial"
    )
    assert _session_status(rows(front="failed", side="failed")) == "failed"


def test_parse_batch_signed_handles_relative_urls_and_errors() -> None:
    payload = [
        {"path": "u/a.jpg", "signedURL": "/object/sign/wardrobe/u/a.jpg?token=t1", "error": None},
        {"path": "u/b.jpg", "signedURL": None, "error": "Either the object does not exist"},
        {"path": "u/c.jpg", "signedUrl": "http://host/storage/v1/object/sign/wardrobe/u/c.jpg?token=t3"},
        "garbage",
    ]
    signed = parse_batch_signed("http://host", payload)
    assert signed == {
        "u/a.jpg": "http://host/storage/v1/object/sign/wardrobe/u/a.jpg?token=t1",
        "u/c.jpg": "http://host/storage/v1/object/sign/wardrobe/u/c.jpg?token=t3",
    }
    assert parse_batch_signed("http://host", {"error": "x"}) == {}
