import pytest
from pydantic import ValidationError

from app.models import StyleProfile, UpdateProfileRequest, UpdateStyleProfileRequest

# The exact JSON the iOS app's JSONEncoder (snake_case keys) produces for a StyleProfile.
IOS_STYLE_PROFILE = {
    "axes": {"silhouette": "first", "finish": "second"},
    "occasions": ["weekend", "work", "eveningsOut"],
    "palettes": ["colour", "earthTones"],
}


def test_accepts_the_ios_encoding_and_normalises_order() -> None:
    profile = StyleProfile.model_validate(IOS_STYLE_PROFILE)

    assert profile.model_dump(mode="json") == {
        "axes": {"silhouette": "first", "finish": "second"},
        "occasions": ["work", "weekend", "eveningsOut"],
        "palettes": ["earthTones", "colour"],
    }


def test_empty_profile_is_valid() -> None:
    assert StyleProfile.model_validate({}).model_dump(mode="json") == {"axes": {}, "occasions": [], "palettes": []}


def test_duplicates_collapse() -> None:
    profile = StyleProfile.model_validate({"occasions": ["work", "work"], "palettes": ["colour", "colour"]})

    assert [occasion.value for occasion in profile.occasions] == ["work"]
    assert [palette.value for palette in profile.palettes] == ["colour"]


@pytest.mark.parametrize(
    "payload",
    [
        {"axes": {"mood": "first"}},
        {"axes": {"silhouette": "third"}},
        {"occasions": ["gym"]},
        {"palettes": ["neon"]},
        {"axes": {}, "unexpected": True},
        {"occasions": "work"},
    ],
)
def test_rejects_unknown_values(payload: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        StyleProfile.model_validate(payload)


def test_style_update_defaults_to_not_completing_onboarding() -> None:
    request = UpdateStyleProfileRequest.model_validate({"style_profile": IOS_STYLE_PROFILE})

    assert request.onboarding_completed is False


@pytest.mark.parametrize("name", ["", "   ", "x" * 81])
def test_display_name_bounds(name: str) -> None:
    with pytest.raises(ValidationError):
        UpdateProfileRequest.model_validate({"display_name": name})


def test_display_name_is_trimmed_and_nullable() -> None:
    assert UpdateProfileRequest.model_validate({"display_name": "  Ada  "}).display_name == "Ada"
    assert UpdateProfileRequest.model_validate({"display_name": None}).display_name is None
