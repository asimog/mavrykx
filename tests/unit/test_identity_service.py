"""The identity use cases, exercised without a database."""

from __future__ import annotations

from types import TracebackType
from typing import Self
from uuid import UUID, uuid4

import pytest

from mavrykx.application.errors import ApplicationError, ErrorCode
from mavrykx.domain.actor import Actor
from mavrykx.modules.identity.contracts import (
    FirmInitRequest,
    MembershipSetRoleRequest,
    SessionCreateRequest,
    SessionRevokeRequest,
    UserDisableRequest,
    UserInviteRequest,
)
from mavrykx.modules.identity.domain import AuthIdentity, FirmId, Role, UserId, UserStatus
from mavrykx.modules.identity.models import FirmRow, MembershipRow, UserRow
from mavrykx.modules.identity.service import IdentityService


class FakeUnitOfWork:
    def __init__(self, session: object) -> None:
        self.session = session
        self.commits = 0
        self.rolled_back = 0

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        return None

    async def commit(self) -> None:
        self.commits += 1

    async def rollback(self) -> None:
        self.rolled_back += 1


class FakeRepository:
    def __init__(self) -> None:
        self.firm: FirmRow | None = None
        self.users: dict[str, UserRow] = {}
        self.memberships: dict[UUID, MembershipRow] = {}
        self.passwords: dict[str, str] = {}
        self.sessions: dict[str, UUID] = {}

    async def firm_exists(self) -> bool:
        return self.firm is not None

    async def add_firm(
        self, name: str, jurisdiction: str | None, default_tz: str = "Asia/Kolkata"
    ) -> FirmRow:
        self.firm = FirmRow(id=uuid4(), name=name, jurisdiction=jurisdiction, default_tz=default_tz)
        return self.firm

    async def find_user_by_email(self, email: str) -> UserRow | None:
        return self.users.get(email.lower())

    async def add_user(
        self, email: str, display_name: str, status: UserStatus = UserStatus.INVITED
    ) -> UserRow:
        row = UserRow(id=uuid4(), email=email, display_name=display_name, status=status.value)
        self.users[email.lower()] = row
        return row

    async def add_membership(
        self, user_id: UUID, firm_id: UUID, role: Role, title: str | None
    ) -> MembershipRow:
        row = MembershipRow(
            id=uuid4(), user_id=user_id, firm_id=firm_id, role=role.value, title=title
        )
        self.memberships[user_id] = row
        return row

    async def find_membership(self, user_id: UUID) -> MembershipRow | None:
        return self.memberships.get(user_id)

    async def find_user(self, user_id: UUID) -> UserRow | None:
        return next((u for u in self.users.values() if u.id == user_id), None)

    async def set_role(self, user_id: UUID, role: Role) -> MembershipRow | None:
        row = self.memberships.get(user_id)
        if row is not None:
            row.role = role.value
        return row

    async def disable_user(self, user_id: UUID) -> UserRow | None:
        row = await self.find_user(user_id)
        if row is not None:
            row.status = UserStatus.DISABLED.value
        return row

    async def create_firm(
        self, name: str, jurisdiction: str | None, admin_email: str, admin_display_name: str
    ) -> UUID:
        if self.firm is not None:
            raise ApplicationError(ErrorCode.FIRM_EXISTS, "the firm is already open")
        self.firm = FirmRow(id=uuid4(), name=name, jurisdiction=jurisdiction, default_tz="UTC")
        user = await self.add_user(admin_email, admin_display_name, UserStatus.INVITED)
        await self.add_membership(user.id, self.firm.id, Role.ADMIN, None)
        return self.firm.id

    async def authenticate(self, email: str, password: str) -> AuthIdentity | None:
        user = self.users.get(email.lower())
        if user is None or self.passwords.get(email.lower()) != password:
            raise ApplicationError(ErrorCode.AUTH_INVALID, "email or password is wrong")
        membership = self.memberships[user.id]
        return AuthIdentity(
            user_id=UserId(user.id), firm_id=FirmId(membership.firm_id), role=Role(membership.role)
        )

    async def create_session(self, user_id: UUID, token_hash: str, _expires_at: object) -> None:
        self.sessions[token_hash] = user_id

    async def session_actor(self, token_hash: str) -> AuthIdentity | None:
        user_id = self.sessions.get(token_hash)
        if user_id is None:
            return None
        membership = self.memberships[user_id]
        return AuthIdentity(
            user_id=UserId(user_id), firm_id=FirmId(membership.firm_id), role=Role(membership.role)
        )

    async def revoke_session(self, token_hash: str) -> bool:
        return self.sessions.pop(token_hash, None) is not None


@pytest.fixture
def repository() -> FakeRepository:
    return FakeRepository()


@pytest.fixture
def service(repository: FakeRepository) -> IdentityService:
    def unit_of_work(_actor: Actor) -> FakeUnitOfWork:
        return FakeUnitOfWork(repository)

    def make_repository(_session: object) -> FakeRepository:
        return repository

    return IdentityService(unit_of_work, make_repository)  # type: ignore[arg-type]


async def test_init_opens_the_firm_with_an_admin(
    service: IdentityService, repository: FakeRepository
) -> None:
    view = await service.init_firm(
        FirmInitRequest(
            firm_name="Acme Legal",
            admin_email="admin@acme.co",
            admin_display_name="A Admin",
        )
    )

    assert view.name == "Acme Legal"
    assert repository.firm is not None
    admin = repository.users["admin@acme.co"]
    assert repository.memberships[admin.id].role == "admin"


async def test_init_refuses_a_second_firm(
    service: IdentityService, repository: FakeRepository
) -> None:
    repository.firm = FirmRow(id=uuid4(), name="Existing", jurisdiction=None, default_tz="UTC")

    with pytest.raises(ApplicationError) as error:
        await service.init_firm(
            FirmInitRequest(
                firm_name="Second",
                admin_email="second@acme.co",
                admin_display_name="Second Admin",
            )
        )

    assert error.value.code is ErrorCode.FIRM_EXISTS


async def _admin(repository: FakeRepository) -> Actor:
    user = await repository.add_user("admin@acme.co", "Admin", UserStatus.ACTIVE)
    firm_id = uuid4()
    await repository.add_membership(user.id, firm_id, Role.ADMIN, None)
    return Actor(user_id=user.id, firm_id=firm_id)


async def test_a_non_admin_cannot_create_an_admin(
    service: IdentityService, repository: FakeRepository
) -> None:
    user = await repository.add_user("staff@acme.co", "Staff", UserStatus.ACTIVE)
    firm_id = uuid4()
    await repository.add_membership(user.id, firm_id, Role.STAFF, None)

    with pytest.raises(ApplicationError) as error:
        await service.invite(
            Actor(user_id=user.id, firm_id=firm_id),
            UserInviteRequest(
                email="new@acme.co", display_name="New", role=Role.ADMIN
            ),
        )

    assert error.value.code is ErrorCode.ROLE_FORBIDDEN


async def test_an_admin_promotes_an_admin(
    service: IdentityService, repository: FakeRepository
) -> None:
    actor = await _admin(repository)
    invited = await service.invite(
        actor,
        UserInviteRequest(email="boss@acme.co", display_name="Boss", role=Role.LAWYER),
    )
    promoted = await service.set_role(
        actor, MembershipSetRoleRequest(user_id=invited.id, role=Role.ADMIN)
    )

    assert promoted.role is Role.ADMIN


async def test_an_invite_refuses_a_duplicate_email(
    service: IdentityService, repository: FakeRepository
) -> None:
    actor = await _admin(repository)
    await repository.add_user("taken@acme.co", "Taken", UserStatus.ACTIVE)

    with pytest.raises(ApplicationError) as error:
        await service.invite(
            actor,
            UserInviteRequest(email="taken@acme.co", display_name="Dup", role=Role.STAFF),
        )

    assert error.value.code is ErrorCode.USER_EMAIL_TAKEN


async def test_disabling_a_user_marks_them_disabled(
    service: IdentityService, repository: FakeRepository
) -> None:
    actor = await _admin(repository)
    invited = await service.invite(
        actor,
        UserInviteRequest(email="temp@acme.co", display_name="Temp", role=Role.STAFF),
    )

    disabled = await service.disable(actor, UserDisableRequest(user_id=invited.id))

    assert disabled.status is UserStatus.DISABLED


async def test_a_session_is_minted_for_a_valid_password(
    service: IdentityService, repository: FakeRepository
) -> None:
    actor = await _admin(repository)
    repository.passwords["admin@acme.co"] = "correct horse"

    view = await service.create_session(
        SessionCreateRequest(email="admin@acme.co", password="correct horse")
    )

    assert view.user_id == actor.user_id
    assert await service.resolve_actor(view.token) == actor


async def test_a_wrong_password_is_refused(
    service: IdentityService, repository: FakeRepository
) -> None:
    await _admin(repository)
    repository.passwords["admin@acme.co"] = "correct horse"

    with pytest.raises(ApplicationError) as error:
        await service.create_session(
            SessionCreateRequest(email="admin@acme.co", password="wrong")
        )

    assert error.value.code is ErrorCode.AUTH_INVALID


async def test_a_revoked_session_stops_resolving(
    service: IdentityService, repository: FakeRepository
) -> None:
    await _admin(repository)
    repository.passwords["admin@acme.co"] = "correct horse"
    view = await service.create_session(
        SessionCreateRequest(email="admin@acme.co", password="correct horse")
    )

    await service.revoke_session(SessionRevokeRequest(token=view.token))

    with pytest.raises(ApplicationError) as error:
        await service.resolve_actor(view.token)

    assert error.value.code is ErrorCode.SESSION_REVOKED
