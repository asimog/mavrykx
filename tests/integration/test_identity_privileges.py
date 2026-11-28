"""The privileged path, proved against a real PostgreSQL as the application role."""

from __future__ import annotations

import os

import pytest
from sqlalchemy import text
from sqlalchemy.exc import ProgrammingError
from sqlalchemy.ext.asyncio import create_async_engine

from mavrykx.application.errors import ApplicationError, ErrorCode
from mavrykx.domain.actor import Actor
from mavrykx.modules.identity.api import (
    FirmInitRequest,
    IdentityService,
    SessionCreateRequest,
    SessionRevokeRequest,
)
from mavrykx.root.runtime import Runtime

PASSWORD = "correct horse battery"
SETUP_URL = "MAVRYKX_SETUP_DATABASE_URL"


@pytest.fixture
def service(runtime: Runtime) -> IdentityService:
    return IdentityService(runtime.unit_of_work)


async def _admin_id(_runtime: Runtime) -> object:
    setup = os.environ.get(SETUP_URL)
    if not setup:
        pytest.skip(f"{SETUP_URL} is not set; the app role cannot read the membership table")
    engine = create_async_engine(setup)
    try:
        async with engine.connect() as connection:
            return await connection.scalar(text("select user_id from app.membership limit 1"))
    finally:
        await engine.dispose()


async def _ensure_admin(runtime: Runtime) -> object:
    user_id = await _admin_id(runtime)
    if user_id is not None:
        return user_id
    setup = os.environ.get(SETUP_URL)
    if not setup:
        pytest.skip(f"{SETUP_URL} is not set; cannot seed the admin membership")
    engine = create_async_engine(setup)
    try:
        async with engine.begin() as connection:
            await connection.execute(text("set role maverick_owner"))
            await connection.execute(
                text(
                    "insert into app.firm (name) select 'Integration Legal' "
                    "where not exists (select 1 from app.firm)"
                )
            )
            await connection.execute(
                text(
                    "insert into app.user (email, display_name, status) "
                    "values ('owner@integration.co', 'Integration Owner', 'invited') "
                    "on conflict (email) do nothing"
                )
            )
            await connection.execute(
                text(
                    "insert into app.membership (user_id, firm_id, role) "
                    "select u.id, f.id, 'admin' from app.user u, app.firm f "
                    "where u.email = 'owner@integration.co' "
                    "on conflict (user_id, firm_id) do nothing"
                )
            )
    finally:
        await engine.dispose()
    return await _admin_id(runtime)


async def _seed_credential(runtime: Runtime, user_id: object) -> None:
    async with runtime.unit_of_work(Actor()) as unit:
        await unit.session.execute(
            text("select app.set_credential(:user_id, :password)"),
            {"user_id": user_id, "password": PASSWORD},
        )
        await unit.commit()


async def test_firm_init_runs_as_the_application_role(
    service: IdentityService, runtime: Runtime
) -> None:
    await _ensure_admin(runtime)

    with pytest.raises(ApplicationError) as error:
        await service.init_firm(
            FirmInitRequest(
                firm_name="Second Firm",
                admin_email="second@integration.co",
                admin_display_name="Second Owner",
            )
        )

    assert error.value.code is ErrorCode.FIRM_EXISTS


async def test_credentials_are_unreadable_by_the_application_role(runtime: Runtime) -> None:
    async with runtime.unit_of_work(Actor()) as unit:
        with pytest.raises(ProgrammingError):
            await unit.session.execute(text("select password_hash from app.user_credential"))


async def test_a_verified_credential_mints_a_live_session(
    service: IdentityService, runtime: Runtime
) -> None:
    user_id = await _ensure_admin(runtime)
    await _seed_credential(runtime, user_id)

    view = await service.create_session(
        SessionCreateRequest(email="owner@integration.co", password=PASSWORD)
    )
    actor = await service.resolve_actor(view.token)

    assert actor.user_id == user_id


async def test_a_revoked_token_stops_resolving(
    service: IdentityService, runtime: Runtime
) -> None:
    user_id = await _ensure_admin(runtime)
    await _seed_credential(runtime, user_id)
    view = await service.create_session(
        SessionCreateRequest(email="owner@integration.co", password=PASSWORD)
    )

    await service.revoke_session(SessionRevokeRequest(token=view.token))

    with pytest.raises(ApplicationError) as error:
        await service.resolve_actor(view.token)
    assert error.value.code is ErrorCode.SESSION_REVOKED
