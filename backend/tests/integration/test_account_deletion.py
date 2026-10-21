from collections.abc import Awaitable, Callable

import asyncpg
import httpx
import pytest

from tests.integration.conftest import AccountUser, sign_in_with_password

pytestmark = pytest.mark.integration

MakeUser = Callable[[], Awaitable[AccountUser]]


async def test_deleting_the_account_removes_the_user_and_their_data(
    client: httpx.AsyncClient,
    make_user: MakeUser,
    auth_http: httpx.AsyncClient,
    admin_http: httpx.AsyncClient,
    superuser_db: asyncpg.Connection,
) -> None:
    user = await make_user()
    bystander = await make_user()
    await client.put("/v1/me/style-profile", headers=user.headers, json={"style_profile": {"palettes": ["colour"]}})

    response = await client.delete("/v1/me", headers=user.headers)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "completed"
    assert "does not cancel" in body["subscription_notice"]

    assert await superuser_db.fetchval("select count(*) from public.profiles where id = $1", user.id) == 0
    assert await superuser_db.fetchval("select count(*) from auth.users where id = $1", user.id) == 0
    assert (await admin_http.get(f"/users/{user.id}")).status_code == 404

    request = await superuser_db.fetchrow(
        "select request_type, status, completed_at from public.privacy_requests where id = $1", body["request_id"]
    )
    assert request is not None
    assert request["request_type"] == "account_deletion"
    assert request["status"] == "completed"
    assert request["completed_at"] is not None

    assert (await client.get("/v1/me", headers=bystander.headers)).status_code == 200


async def test_sessions_stop_working_after_deletion(
    client: httpx.AsyncClient, make_user: MakeUser, auth_http: httpx.AsyncClient
) -> None:
    user = await make_user()

    assert (await client.delete("/v1/me", headers=user.headers)).status_code == 200

    stale_access = await client.get("/v1/me", headers=user.headers)
    assert stale_access.status_code == 401
    assert stale_access.json()["code"] == "session_revoked"

    refreshed = await auth_http.post(
        "/token", params={"grant_type": "refresh_token"}, json={"refresh_token": user.refresh_token}
    )
    assert refreshed.status_code >= 400

    signed_in = await sign_in_with_password(auth_http, user.email, user.password)
    assert signed_in.status_code >= 400


async def test_deletion_is_safe_to_retry(client: httpx.AsyncClient, make_user: MakeUser) -> None:
    user = await make_user()

    first = await client.delete("/v1/me", headers=user.headers)
    second = await client.delete("/v1/me", headers=user.headers)

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["status"] == "completed"
