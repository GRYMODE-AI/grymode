from __future__ import annotations  # asyncpg's runtime classes aren't generic; only the stubs are

import json
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import asyncpg
from asyncpg.pool import PoolConnectionProxy

from app.errors import service_unavailable

logger = logging.getLogger("grymode.db")

type DBConnection = asyncpg.Connection[asyncpg.Record] | PoolConnectionProxy[asyncpg.Record]

_UNAVAILABLE_ERRORS: tuple[type[BaseException], ...] = (
    OSError,
    TimeoutError,
    asyncpg.CannotConnectNowError,
    asyncpg.ConnectionDoesNotExistError,
    asyncpg.TooManyConnectionsError,
    asyncpg.InterfaceError,
)


async def _init_connection(connection: asyncpg.Connection[asyncpg.Record]) -> None:
    await connection.set_type_codec("jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog")


class Database:
    """Postgres access through the ``grymode_api`` role.

    User-scoped work runs inside a transaction that switches to the ``authenticated`` role
    and carries the verified JWT claims, so row level security applies exactly as it does
    for Supabase's own APIs. Service work (privacy requests) runs as ``grymode_api``, which
    can only touch the tables it has been granted.
    """

    def __init__(self, dsn: str, *, min_size: int, max_size: int) -> None:
        self._dsn = dsn
        self._min_size = min_size
        self._max_size = max_size
        self._pool: asyncpg.Pool[asyncpg.Record] | None = None

    async def connect(self) -> None:
        # statement_cache_size=0 keeps the pool compatible with Supabase's transaction pooler.
        self._pool = await asyncpg.create_pool(
            self._dsn,
            min_size=self._min_size,
            max_size=self._max_size,
            statement_cache_size=0,
            command_timeout=10,
            server_settings={"application_name": "grymode-api"},
            init=_init_connection,
        )

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None

    @asynccontextmanager
    async def as_user(self, claims: dict[str, Any]) -> AsyncIterator[DBConnection]:
        async with self._transaction() as connection:
            await connection.execute(
                "select set_config('request.jwt.claims', $1, true), set_config('role', 'authenticated', true)",
                json.dumps(claims),
            )
            yield connection

    @asynccontextmanager
    async def as_service(self) -> AsyncIterator[DBConnection]:
        async with self._transaction() as connection:
            yield connection

    @asynccontextmanager
    async def _transaction(self) -> AsyncIterator[DBConnection]:
        if self._pool is None:
            raise service_unavailable()
        try:
            async with self._pool.acquire() as connection, connection.transaction():
                yield connection
        except _UNAVAILABLE_ERRORS as exc:
            logger.warning("database_unavailable", extra={"error_type": type(exc).__name__})
            raise service_unavailable() from exc
