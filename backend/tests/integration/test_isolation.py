import json
from collections.abc import Awaitable, Callable

import asyncpg
import httpx
import pytest

from app.db import Database
from tests.integration.conftest import AccountUser, LocalStack

pytestmark = pytest.mark.integration

MakeUser = Callable[[], Awaitable[AccountUser]]


async def test_users_only_ever_see_and_change_their_own_profile(client: httpx.AsyncClient, make_user: MakeUser) -> None:
    alice = await make_user()
    bob = await make_user()

    await client.put("/v1/me/style-profile", headers=alice.headers, json={"style_profile": {"palettes": ["neutrals"]}})
    await client.patch("/v1/me", headers=bob.headers, json={"display_name": "Bob"})

    alice_view = (await client.get("/v1/me", headers=alice.headers)).json()
    bob_view = (await client.get("/v1/me", headers=bob.headers)).json()

    assert alice_view["id"] == str(alice.id)
    assert alice_view["display_name"] is None
    assert alice_view["style_profile"]["palettes"] == ["neutrals"]
    assert bob_view["id"] == str(bob.id)
    assert bob_view["display_name"] == "Bob"
    assert bob_view["style_profile"]["palettes"] == []


async def test_row_level_security_scopes_the_api_role_to_the_token_owner(
    stack: LocalStack, make_user: MakeUser
) -> None:
    alice = await make_user()
    bob = await make_user()
    database = Database(stack.api_role_dsn, min_size=1, max_size=2)
    await database.connect()
    try:
        claims = {"sub": str(alice.id), "role": "authenticated", "aud": "authenticated"}
        async with database.as_user(claims) as connection:
            visible = await connection.fetch("select id from public.profiles")
            updated = await connection.execute(
                "update public.profiles set display_name = 'hijacked' where id = $1", bob.id
            )

        assert [row["id"] for row in visible] == [alice.id]
        assert updated == "UPDATE 0"
    finally:
        await database.close()


async def test_api_role_cannot_read_profiles_without_a_user_context(stack: LocalStack) -> None:
    database = Database(stack.api_role_dsn, min_size=1, max_size=1)
    await database.connect()
    try:
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            async with database.as_service() as connection:
                await connection.fetch("select id from public.profiles")
    finally:
        await database.close()


async def test_api_role_cannot_touch_auth_tables(stack: LocalStack) -> None:
    connection = await asyncpg.connect(stack.api_role_dsn)
    try:
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            await connection.fetch("select id from auth.users limit 1")
    finally:
        await connection.close()


async def test_a_token_for_one_user_cannot_be_replayed_with_another_users_claims(
    client: httpx.AsyncClient, make_user: MakeUser, superuser_db: asyncpg.Connection
) -> None:
    alice = await make_user()
    bob = await make_user()
    header, _, signature = alice.access_token.split(".")
    bob_payload = bob.access_token.split(".")[1]

    response = await client.get("/v1/me", headers={"Authorization": f"Bearer {header}.{bob_payload}.{signature}"})

    assert response.status_code == 401
    row = await superuser_db.fetchrow("select style_profile from public.profiles where id = $1", bob.id)
    assert row is not None
    assert json.loads(row["style_profile"]) == {}
