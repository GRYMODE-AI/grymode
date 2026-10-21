import uuid
from typing import Any

import pytest
from pydantic import SecretStr, ValidationError

from app.ai_outfit_composer import composer_schema, style_brief, validate_outfits, wardrobe_brief
from app.config import AIProvider, Environment, Settings
from app.extraction import extraction_schema, parse_extraction
from app.models import StyleProfile
from app.openai_client import AIProviderError, _output_text
from app.wardrobe_models import Formality, GarmentCategory


def _garment(category: str, **extra: Any) -> dict[str, Any]:
    return {"id": uuid.uuid4(), "category": category, **extra}


def _settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "environment": Environment.TEST,
        "supabase_url": "http://supabase.test",
        "supabase_secret_key": SecretStr("unit-test-secret"),
        "database_url": SecretStr("postgresql://unused@127.0.0.1:1/unused"),
    }
    values.update(overrides)
    return Settings.model_validate(values)


# --- settings ---


def test_openai_provider_requires_real_key() -> None:
    with pytest.raises(ValidationError):
        _settings(ai_provider="openai", ai_api_key=None)
    with pytest.raises(ValidationError):
        _settings(ai_provider="openai", ai_api_key=SecretStr("sk-proj-REPLACE-WITH-YOUR-OPENAI-PROJECT-KEY"))


def test_openai_provider_accepts_key() -> None:
    settings = _settings(ai_provider="openai", ai_api_key=SecretStr("sk-test-123"))
    assert settings.ai_provider is AIProvider.OPENAI


# --- extraction ---


def test_parse_extraction_normalises_labels() -> None:
    payload = {
        "garments": [
            {
                "category": "outerwear",
                "subcategory": "  Double-Breasted   Blazer ",
                "primary_color": "Navy",
                "secondary_colors": ["navy", "Gold", "gold"],
                "pattern": None,
                "material": "Wool",
                "silhouette": "tailored",
                "formality": "smartCasual",
                "season_tags": ["autumn", "winter", "monsoon"],
                "style_tags": ["Tailored", "classic"],
                "confidence": 1.7,
            }
        ]
    }
    [garment] = parse_extraction(payload, max_items=4)
    assert garment.category is GarmentCategory.OUTERWEAR
    assert garment.subcategory == "double-breasted blazer"
    assert garment.primary_color == "navy"
    assert garment.secondary_colors == ("gold",)
    assert garment.material == "wool"
    assert garment.formality is Formality.SMART_CASUAL
    assert garment.season_tags == ("autumn", "winter")
    assert garment.confidence == 1.0


def test_parse_extraction_drops_invalid_and_caps() -> None:
    item = {"category": "tops", "formality": "black-tie", "confidence": "high"}
    payload = {"garments": [{"category": "uncategorised"}, {"category": "hats"}, item, item, item]}
    garments = parse_extraction(payload, max_items=3)
    assert len(garments) == 1
    assert garments[0].formality is None
    assert garments[0].confidence is None


def test_parse_extraction_rejects_wrong_shape() -> None:
    with pytest.raises(AIProviderError):
        parse_extraction({"items": []}, max_items=4)


def test_schemas_are_strict_objects() -> None:
    for schema in (extraction_schema(), composer_schema()):
        assert schema["additionalProperties"] is False
        assert schema["required"] == list(schema["properties"].keys())


# --- outfit composer ---


def _wardrobe() -> list[dict[str, Any]]:
    return [
        _garment("tops", primary_color="white"),  # g1
        _garment("bottoms", primary_color="navy"),  # g2
        _garment("shoes", primary_color="brown"),  # g3
        _garment("dresses", primary_color="black"),  # g4
        _garment("knitwear", primary_color="cream"),  # g5
        _garment("outerwear", primary_color="camel"),  # g6
        _garment("bottoms", primary_color="black"),  # g7
    ]


def _outfit(refs: list[str], **extra: Any) -> dict[str, Any]:
    return {
        "title": "Quiet weekday",
        "piece_refs": refs,
        "occasion_tags": ["Work"],
        "context_tags": ["Daytime"],
        "style_tags": ["minimal"],
        "score": 0.8,
        **extra,
    }


def test_validate_outfits_assigns_slots_and_orders() -> None:
    garments = _wardrobe()
    _, by_ref = wardrobe_brief(garments)
    [look] = validate_outfits({"outfits": [_outfit(["g6", "g3", "g2", "g1"])]}, by_ref, max_outfits=16)
    assert [p["slot"] for p in look["garments"]] == ["primary", "bottom", "footwear", "outerwear"]
    assert [p["position"] for p in look["garments"]] == [0, 1, 2, 3]
    assert look["style_tags"] == ["Minimal"]


def test_validate_outfits_layers_knit_over_top() -> None:
    _, by_ref = wardrobe_brief(_wardrobe())
    [look] = validate_outfits({"outfits": [_outfit(["g1", "g5", "g2"])]}, by_ref, max_outfits=16)
    slots = {str(p["garment_id"]): p["slot"] for p in look["garments"]}
    assert slots[str(by_ref["g5"]["id"])] == "outerwear"


@pytest.mark.parametrize(
    "refs",
    [
        ["g1"],  # top without bottom
        ["g4", "g2"],  # dress with bottom
        ["g1", "g2", "g7"],  # two bottoms
        ["g1", "g2", "g99"],  # unknown ref
        ["g1", "g2", "g2"],  # duplicate ref
        ["g1", "g5", "g2", "g6"],  # knit layer plus coat
        [],
    ],
)
def test_validate_outfits_rejects_incomplete_or_invalid(refs: list[str]) -> None:
    _, by_ref = wardrobe_brief(_wardrobe())
    assert validate_outfits({"outfits": [_outfit(refs)]}, by_ref, max_outfits=16) == []


def test_validate_outfits_dedupes_sorts_and_caps() -> None:
    _, by_ref = wardrobe_brief(_wardrobe())
    payload = {
        "outfits": [
            _outfit(["g1", "g2"], score=0.4),
            _outfit(["g2", "g1"], score=0.9),  # same pieces, different order
            _outfit(["g4", "g3"], score=0.95, occasion_tags=["Nightclub"], title="  "),
            _outfit(["g1", "g7", "g3"], score=5),
        ]
    }
    looks = validate_outfits(payload, by_ref, max_outfits=2)
    assert len(looks) == 2
    assert looks[0]["score"] == 1.0
    assert looks[1]["score"] == 0.95
    assert looks[1]["occasion_tags"] == ["Casual"]
    assert looks[1]["title"] == "Wardrobe look"


def test_wardrobe_brief_uses_refs_not_ids() -> None:
    garments = _wardrobe()
    brief, by_ref = wardrobe_brief(garments)
    assert [g["ref"] for g in brief] == [f"g{i}" for i in range(1, len(garments) + 1)]
    assert all("id" not in g for g in brief)
    assert by_ref["g1"] is garments[0]


def test_style_brief_uses_human_labels() -> None:
    profile = StyleProfile.model_validate(
        {"axes": {"silhouette": "second", "finish": "first"}, "occasions": ["work"], "palettes": ["neutrals"]}
    )
    assert style_brief(profile) == {
        "style_direction": ["Structured", "Effortless"],
        "occasions": ["Work"],
        "palettes": ["Neutrals"],
    }


# --- client parsing ---


def test_output_text_handles_refusal_and_empty() -> None:
    with pytest.raises(AIProviderError, match="ai_refused"):
        _output_text({"output": [{"type": "message", "content": [{"type": "refusal", "refusal": "no"}]}]})
    with pytest.raises(AIProviderError, match="ai_empty_output"):
        _output_text({"output": [{"type": "reasoning"}]})
    text = _output_text({"output": [{"type": "message", "content": [{"type": "output_text", "text": "{}"}]}]})
    assert text == "{}"
