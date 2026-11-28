"""The identity use cases: open the firm, invite, disable, re-role and sign in."""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from mavrykx.application.errors import ApplicationError, ErrorCode
from mavrykx.domain.actor import Actor
from mavrykx.infrastructure.tokens import hash_session_token, new_session_token
from mavrykx.infrastructure.unit_of_work import SqlAlchemyUnitOfWork
from mavrykx.modules.identity.contracts import (
    FirmInitRequest,
    FirmView,
    MembershipSetRoleRequest,
    MembershipView,
    SessionCreateRequest,
    SessionRevoked,
    SessionRevokeRequest,
    SessionView,
    UserDisableRequest,
    UserInviteRequest,
    UserView,
)
from mavrykx.modules.identity.domain import Role, UserStatus, may_change_role
from mavrykx.modules.identity.models import MembershipRow, UserRow
from mavrykx.modules.identity.repository import IdentityRepository

RepositoryFactory = Callable[[AsyncSession], IdentityRepository]
SESSION_TTL = timedelta(days=7)


class IdentityService:
    """Owns the identity use cases and their transactions."""

    def __init__(
        self,
        unit_of_work: Callable[[Actor], SqlAlchemyUnitOfWork],
        repository_factory: RepositoryFactory = IdentityRepository,
    ) -> None:
        self._unit_of_work = unit_of_work
        self._repository_factory = repository_factory

    async def init_firm(self, request: FirmInitRequest) -> FirmView:
        """Open the installation with its firm and first admin."""
        async with self._unit_of_work(Actor()) as unit:
            repository = self._repository_factory(unit.session)
            firm_id = await repository.create_firm(
                request.firm_name,
                request.jurisdiction,
                str(request.admin_email),
                request.admin_display_name,
            )
            await unit.commit()
            return FirmView(
                id=firm_id,
                name=request.firm_name,
                jurisdiction=request.jurisdiction,
                default_tz="Asia/Kolkata",
            )

    async def invite(self, actor: Actor, request: UserInviteRequest) -> UserView:
        """Invite a user and give them their one role."""
        async with self._unit_of_work(actor) as unit:
            repository = self._repository_factory(unit.session)
            actor_role = await self._require_admin(actor, repository)
            if not may_change_role(actor_role, request.role):
                raise ApplicationError(
                    ErrorCode.ROLE_FORBIDDEN, "only an admin may create another admin"
                )
            if await repository.find_user_by_email(str(request.email)) is not None:
                raise ApplicationError(ErrorCode.USER_EMAIL_TAKEN, "that email is already in use")
            user = await repository.add_user(str(request.email), request.display_name)
            await repository.add_membership(
                user.id, self._firm_id(actor), request.role, request.title
            )
            await unit.commit()
            return self._user_view(user, request.role)

    async def disable(self, actor: Actor, request: UserDisableRequest) -> UserView:
        """Disable a user and their membership."""
        async with self._unit_of_work(actor) as unit:
            repository = self._repository_factory(unit.session)
            await self._require_admin(actor, repository)
            user = await repository.disable_user(request.user_id)
            if user is None:
                raise ApplicationError(ErrorCode.USER_NOT_FOUND, "no such user")
            membership = await repository.find_membership(request.user_id)
            role = Role(membership.role) if membership is not None else Role.STAFF
            await unit.commit()
            return self._user_view(user, role)

    async def set_role(self, actor: Actor, request: MembershipSetRoleRequest) -> MembershipView:
        """Change a user's role, refusing to mint another admin without admin rights."""
        async with self._unit_of_work(actor) as unit:
            repository = self._repository_factory(unit.session)
            actor_role = await self._require_admin(actor, repository)
            if not may_change_role(actor_role, request.role):
                raise ApplicationError(
                    ErrorCode.ROLE_FORBIDDEN, "only an admin may promote an admin"
                )
            row = await repository.set_role(request.user_id, request.role)
            if row is None:
                raise ApplicationError(ErrorCode.USER_NOT_FOUND, "no such membership")
            await unit.commit()
            return self._membership_view(row)

    async def create_session(self, request: SessionCreateRequest) -> SessionView:
        """Verify a password in the database and mint a session token."""
        async with self._unit_of_work(Actor()) as unit:
            repository = self._repository_factory(unit.session)
            identity = await repository.authenticate(str(request.email), request.password)
            if identity is None:
                raise ApplicationError(ErrorCode.AUTH_INVALID, "email or password is wrong")
            token = new_session_token()
            expires_at = datetime.now(UTC) + SESSION_TTL
            await repository.create_session(
                identity.user_id, hash_session_token(token), expires_at
            )
            await unit.commit()
            return SessionView(
                token=token,
                expires_at=expires_at,
                user_id=identity.user_id,
                firm_id=identity.firm_id,
                role=identity.role,
            )

    async def resolve_actor(self, token: str) -> Actor:
        """Resolve a live session token to the actor it acts as."""
        async with self._unit_of_work(Actor()) as unit:
            repository = self._repository_factory(unit.session)
            identity = await repository.session_actor(hash_session_token(token))
            if identity is None:
                raise ApplicationError(ErrorCode.SESSION_REVOKED, "the session is not live")
            return Actor(user_id=identity.user_id, firm_id=identity.firm_id)

    async def revoke_session(self, request: SessionRevokeRequest) -> SessionRevoked:
        """Revoke one session."""
        async with self._unit_of_work(Actor()) as unit:
            repository = self._repository_factory(unit.session)
            revoked = await repository.revoke_session(hash_session_token(request.token))
            await unit.commit()
            if not revoked:
                raise ApplicationError(ErrorCode.SESSION_REVOKED, "the session is not live")
            return SessionRevoked(revoked=True)

    async def actor_from_header(self, header: str | None) -> Actor:
        """Resolve the bearer token a surface received, or refuse."""
        if header is None or not header.startswith("Bearer "):
            raise ApplicationError(ErrorCode.AUTH_INVALID, "a bearer token is required")
        return await self.resolve_actor(header[7:].strip())

    async def _require_admin(self, actor: Actor, repository: IdentityRepository) -> Role:
        """Return the actor's role, refusing anyone who is not an active admin."""
        if actor.user_id is None:
            raise ApplicationError(ErrorCode.AUTH_INVALID, "this operation needs a user")
        membership = await repository.find_membership(actor.user_id)
        if membership is None or membership.disabled_at is not None:
            raise ApplicationError(ErrorCode.AUTH_INVALID, "the actor is not a firm member")
        role = Role(membership.role)
        if role is not Role.ADMIN:
            raise ApplicationError(ErrorCode.ROLE_FORBIDDEN, "only an admin may do this")
        return role

    @staticmethod
    def _firm_id(actor: Actor) -> UUID:
        """Return the firm the actor acts in."""
        if actor.firm_id is None:
            raise ApplicationError(ErrorCode.AUTH_INVALID, "the actor has no firm")
        return actor.firm_id

    @staticmethod
    def _user_view(user: UserRow, role: Role) -> UserView:
        return UserView(
            id=user.id,
            email=user.email,
            display_name=user.display_name,
            status=UserStatus(user.status),
            role=role,
        )

    @staticmethod
    def _membership_view(row: MembershipRow) -> MembershipView:
        return MembershipView(
            user_id=row.user_id,
            role=Role(row.role),
            title=row.title,
            disabled_at=row.disabled_at,
        )
