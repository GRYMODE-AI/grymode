from collections.abc import Awaitable, Callable

import httpx
import pytest

from tests.integration.conftest import AccountUser

pytestmark = pytest.mark.integration

MakeUser = Callable[[], Awaitable[AccountUser]]

STYLE = {
    "axes": {"silhouette": "first", "finish": "second"},
    "occasions": ["weekend", "work"],
    "palettes": ["neutrals"],
}


async def test_new_user_gets_an_empty_profile(client: httpx.AsyncClient, make_user: MakeUser) -> None:
    user = await make_user()

    response = await client.get("/v1/me", headers=user.headers)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["id"] == str(user.id)
    assert body["email"] == user.email
    assert body["display_name"] is None
    assert body["style_profile"] == {"axes": {}, "occasions": [], "palettes": []}
    assert body["onboarding_completed_at"] is None


async def test_style_profile_round_trip(client: httpx.AsyncClient, make_user: MakeUser) -> None:
    user = await make_user()

    saved = await client.put(
        "/v1/me/style-profile", headers=user.headers, json={"style_profile": STYLE, "onboarding_completed": True}
    )
    fetched = await client.get("/v1/me", headers=user.headers)

    assert saved.status_code == 200, saved.text
    assert fetched.json()["style_profile"] == {
        "axes": {"silhouette": "first", "finish": "second"},
        "occasions": ["work", "weekend"],
        "palettes": ["neutrals"],
    }
    completed_at = fetched.json()["onboarding_completed_at"]
    assert completed_at is not None

    edited = await client.put(
        "/v1/me/style-profile", headers=user.headers, json={"style_profile": {"palettes": ["colour"]}}
    )
    assert edited.json()["style_profile"]["palettes"] == ["colour"]
    assert edited.json()["onboarding_completed_at"] == completed_at


async def test_display_name_can_be_set_and_cleared(client: httpx.AsyncClient, make_user: MakeUser) -> None:
    user = await make_user()

    named = await client.patch("/v1/me", headers=user.headers, json={"display_name": "  Ada  "})
    cleared = await client.patch("/v1/me", headers=user.headers, json={"display_name": None})

    assert named.json()["display_name"] == "Ada"
    assert cleared.json()["display_name"] is None


async def test_rejects_invalid_style_values(client: httpx.AsyncClient, make_user: MakeUser) -> None:
    user = await make_user()

    response = await client.put(
        "/v1/me/style-profile", headers=user.headers, json={"style_profile": {"axes": {"mood": "first"}}}
    )

    assert response.status_code == 422
    assert response.json()["code"] == "invalid_request"
