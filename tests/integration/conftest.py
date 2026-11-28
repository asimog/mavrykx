"""Integration fixtures: a real PostgreSQL, reached as the application role.

Set `MAVRYKX_APP_DATABASE_URL` to a migrated database and a login role that is a member of
`maverick_app`. Without it every test here skips with the fix, never passes silently.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator

import pytest

from mavrykx.domain.actor import Actor
from mavrykx.infrastructure.settings import Settings
from mavrykx.infrastructure.unit_of_work import SqlAlchemyUnitOfWork
from mavrykx.root.runtime import Runtime

APP_URL = "MAVRYKX_APP_DATABASE_URL"


def app_url() -> str:
    """Return the application DSN or skip with the exact fix."""
    url = os.environ.get(APP_URL)
    if not url:
        pytest.skip(
            f"{APP_URL} is not set; start PostgreSQL, run alembic upgrade head, "
            "create a login role in maverick_app and set the URL"
        )
    return url


@pytest.fixture
async def runtime() -> AsyncIterator[Runtime]:
    """The runtime over the migrated database."""
    settings = Settings(database_url=app_url())
    runtime = Runtime(settings)
    try:
        yield runtime
    finally:
        await runtime.dispose()


@pytest.fixture
def unit_of_work(runtime: Runtime) -> SqlAlchemyUnitOfWork:
    """One unit of work as an installation actor."""
    return runtime.unit_of_work(Actor())
