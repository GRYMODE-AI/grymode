import os
import secrets
import shutil
import subprocess
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path

import asyncpg
import httpx
import pytest
from fastapi import FastAPI
from pydantic import SecretStr

from app.config import AIProvider, Environment, Settings
from app.main import create_app

REPO_ROOT = Path(__file__).resolve().parents[3]
# Local-only password set by supabase/seed.sql. Deployed environments use Secret Manager.
LOCAL_API_ROLE_PASSWORD = "grymode-local-dev-only"


@dataclass(frozen=True)
class LocalStack:
    api_url: str
    publishable_key: str
    secret_key: str
    superuser_dsn: str
    api_role_dsn: str
    mail_url: str


@dataclass(frozen=True)
class AccountUser:
    id: uuid.UUID
    email: str
    password: str
    access_token: str
    refresh_token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.access_token}"}


def _read_supabase_status() -> dict[str, str] | None:
    executable = shutil.which("supabase") or str(Path.home() / ".local/bin/supabase")
    if not Path(executable).exists():
        return None
    result = subprocess.run(  # noqa: S603 - fixed argv, no shell
        [executable, "status", "-o", "env"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if result.returncode != 0:
        return None
    values: dict[str, str] = {}
    for line in result.stdout.splitlines():
        name, sep, value = line.partition("=")
        if sep:
            values[name.strip()] = value.strip().strip('"')
    return values


@pytest.fixture(scope="session")
def stack() -> LocalStack:
    status = _read_supabase_status()
    if not status or "API_URL" not in status:
        message = "Local Supabase is not running. Start it with `supabase start` from the repository root."
        if os.environ.get("GRYMODE_REQUIRE_INTEGRATION") == "1":
            pytest.fail(message)
        pytest.skip(message)

    db_url = status["DB_URL"]
    return LocalStack(
        api_url=status["API_URL"].rstrip("/"),
        publishable_key=status.get("PUBLISHABLE_KEY") or status["ANON_KEY"],
        secret_key=status.get("SECRET_KEY") or status["SERVICE_ROLE_KEY"],
        superuser_dsn=db_url,
        api_role_dsn=db_url.replace("postgres:postgres@", f"grymode_api:{LOCAL_API_ROLE_PASSWORD}@", 1),
        mail_url=(status.get("MAILPIT_URL") or status["INBUCKET_URL"]).rstrip("/"),
    )


@pytest.fixture(scope="session")
async def app(stack: LocalStack) -> AsyncIterator[FastAPI]:
    settings = Settings(
        environment=Environment.TEST,
        supabase_url=stack.api_url,
        supabase_secret_key=SecretStr(stack.secret_key),
        database_url=SecretStr(stack.api_role_dsn),
        log_level="WARNING",
        rate_limit_requests_per_minute=10_000,
        ai_provider=AIProvider.LOCAL,
    )
    application = create_app(settings)
    async with application.router.lifespan_context(application):
        yield application


@pytest.fixture(scope="session")
async def client(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://api.test") as http:
        yield http


@pytest.fixture(scope="session")
async def auth_http(stack: LocalStack) -> AsyncIterator[httpx.AsyncClient]:
    """A client for Supabase Auth itself, authenticated with the public publishable key,
    exactly as the iOS app talks to it."""
    async with httpx.AsyncClient(
        base_url=f"{stack.api_url}/auth/v1", headers={"apikey": stack.publishable_key}
    ) as http:
        yield http


@pytest.fixture(scope="session")
async def admin_http(stack: LocalStack) -> AsyncIterator[httpx.AsyncClient]:
    headers = {"apikey": stack.secret_key}
    if stack.secret_key.count(".") == 2:
        headers["Authorization"] = f"Bearer {stack.secret_key}"
    async with httpx.AsyncClient(base_url=f"{stack.api_url}/auth/v1/admin", headers=headers) as http:
        yield http


@pytest.fixture(scope="session")
async def superuser_db(stack: LocalStack) -> AsyncIterator[asyncpg.Connection]:
    connection = await asyncpg.connect(stack.superuser_dsn)
    yield connection
    await connection.close()


async def sign_in_with_password(auth_http: httpx.AsyncClient, email: str, password: str) -> httpx.Response:
    return await auth_http.post(
        "/token", params={"grant_type": "password"}, json={"email": email, "password": password}
    )


@pytest.fixture
async def make_user(
    auth_http: httpx.AsyncClient, admin_http: httpx.AsyncClient
) -> AsyncIterator[Callable[[], Awaitable[AccountUser]]]:
    created: list[uuid.UUID] = []

    async def factory() -> AccountUser:
        email = f"test-{uuid.uuid4().hex[:12]}@grymode.test"
        password = secrets.token_urlsafe(18) + "a1"
        response = await admin_http.post("/users", json={"email": email, "password": password, "email_confirm": True})
        assert response.status_code == 200, response.text
        user_id = uuid.UUID(response.json()["id"])
        created.append(user_id)

        session = await sign_in_with_password(auth_http, email, password)
        assert session.status_code == 200, session.text
        body = session.json()
        return AccountUser(user_id, email, password, body["access_token"], body["refresh_token"])

    yield factory

    for user_id in created:
        await admin_http.delete(f"/users/{user_id}")
