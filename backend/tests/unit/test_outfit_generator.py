import uuid
from typing import Any

from app.models import Occasion, StyleProfile
from app.outfit_generator import compose_candidates
from app.outfit_models import OutfitSlot


def _garment(category: str, *, color: str | None = None, formality: str | None = None) -> dict[str, Any]:
    return {
        "id": uuid.uuid4(),
        "category": category,
        "primary_color": color,
        "formality": formality,
        "season_tags": [],
        "style_tags": [],
        "image_object_key": f"{category}/original.jpg",
    }


def test_compose_candidates_only_uses_provided_garment_ids() -> None:
    top = _garment("tops", color="navy")
    bottom = _garment("bottoms", color="black")
    shoes = _garment("shoes", color="white")
    style = StyleProfile(occasions=[Occasion.WEEKEND])

    looks = compose_candidates([top, bottom, shoes], style)
    assert looks
    owned = {top["id"], bottom["id"], shoes["id"]}
    for look in looks:
        ids = {piece.garment_id for piece in look.garments}
        assert ids <= owned
        assert look.signature
        assert 0 <= look.score <= 1


def test_compose_candidates_deduplicates_signatures() -> None:
    top = _garment("tops")
    bottom = _garment("bottoms")
    shoes = _garment("shoes")
    looks = compose_candidates([top, bottom, shoes], StyleProfile())
    signatures = [look.signature for look in looks]
    assert len(signatures) == len(set(signatures))


def test_compose_candidates_builds_dress_looks() -> None:
    dress = _garment("dresses", formality="formal")
    shoes = _garment("shoes")
    looks = compose_candidates([dress, shoes], StyleProfile(occasions=[Occasion.SPECIAL_OCCASIONS]))
    assert looks
    assert any(any(p.slot == OutfitSlot.PRIMARY and p.category == "dresses" for p in look.garments) for look in looks)


def test_compose_candidates_empty_without_compatible_pairs() -> None:
    looks = compose_candidates([_garment("shoes"), _garment("bags")], StyleProfile())
    assert looks == []
