import logging
import uuid

import httpx
from pydantic import SecretStr

from app.errors import service_unavailable

logger = logging.getLogger("grymode.supabase_admin")


class SupabaseAdmin:
    """The small slice of the Supabase Auth admin API the service needs.

    Uses the project's secret key, which lives only in the backend's environment
    (Secret Manager in deployed environments).
    """

    def __init__(self, *, base_url: str, secret_key: SecretStr, http: httpx.AsyncClient) -> None:
        self._base_url = base_url
        self._secret_key = secret_key
        self._http = http

    def _headers(self) -> dict[str, str]:
        key = self._secret_key.get_secret_value()
        headers = {"apikey": key}
        # Legacy service_role keys are JWTs and must also be sent as a bearer token.
        # New-style secret keys (sb_secret_...) are accepted through the apikey header alone.
        if key.count(".") == 2:
            headers["Authorization"] = f"Bearer {key}"
        return headers

    async def delete_user(self, user_id: uuid.UUID) -> None:
        """Hard-deletes the auth user, which revokes their refresh tokens and cascades to
        every table keyed on ``auth.users``. Deleting a user that no longer exists succeeds."""
        try:
            response = await self._http.delete(
                f"{self._base_url}/auth/v1/admin/users/{user_id}",
                headers=self._headers(),
                timeout=10.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("auth_admin_unreachable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc

        if response.status_code == 404 or response.is_success:
            return
        logger.error("auth_admin_delete_failed", extra={"status": response.status_code})
        raise service_unavailable()
