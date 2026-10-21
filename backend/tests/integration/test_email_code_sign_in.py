import asyncio
import re
import uuid

import httpx
import pytest

from tests.integration.conftest import LocalStack

pytestmark = pytest.mark.integration

_CODE = re.compile(r"\b(\d{6})\b")


async def _wait_for_code(stack: LocalStack, email: str) -> tuple[str, str]:
    async with httpx.AsyncClient(base_url=stack.mail_url) as mail:
        for _ in range(40):
            found = await mail.get("/api/v1/search", params={"query": f'to:"{email}"'})
            messages = found.json().get("messages", []) if found.status_code == 200 else []
            if messages:
                message = (await mail.get(f"/api/v1/message/{messages[0]['ID']}")).json()
                match = _CODE.search(message.get("Text") or "")
                assert match, "sign-in email did not contain a 6-digit code"
                return message["Subject"], match.group(1)
            await asyncio.sleep(0.25)
    pytest.fail(f"no sign-in email arrived for {email}")


async def test_email_code_sign_in_creates_an_account_the_api_accepts(
    stack: LocalStack, auth_http: httpx.AsyncClient, admin_http: httpx.AsyncClient, client: httpx.AsyncClient
) -> None:
    email = f"code-{uuid.uuid4().hex[:12]}@grymode.test"

    requested = await auth_http.post("/otp", json={"email": email, "create_user": True})
    assert requested.status_code == 200, requested.text

    subject, code = await _wait_for_code(stack, email)
    assert subject == "Your Grymode sign-in code"

    wrong = await auth_http.post("/verify", json={"type": "email", "email": email, "token": "000000"})
    assert wrong.status_code >= 400

    verified = await auth_http.post("/verify", json={"type": "email", "email": email, "token": code})
    assert verified.status_code == 200, verified.text
    session = verified.json()
    try:
        me = await client.get("/v1/me", headers={"Authorization": f"Bearer {session['access_token']}"})
        assert me.status_code == 200, me.text
        assert me.json()["email"] == email

        reused = await auth_http.post("/verify", json={"type": "email", "email": email, "token": code})
        assert reused.status_code >= 400
    finally:
        await admin_http.delete(f"/users/{session['user']['id']}")
