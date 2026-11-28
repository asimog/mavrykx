"""The identity repository. The only file here that knows SQLAlchemy."""

from __future__ import annotations

from datetime import datetime
from typing import cast
from uuid import UUID

from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession

from mavrykx.application.errors import ApplicationError, ErrorCode
from mavrykx.modules.identity.domain import AuthIdentity, FirmId, Role, UserId, UserStatus
from mavrykx.modules.identity.models import FirmRow, MembershipRow, UserRow

_KNOWN = {
    "FIRM_EXISTS": ErrorCode.FIRM_EXISTS,
    "AUTH_INVALID": ErrorCode.AUTH_INVALID,
    "USER_DISABLED": ErrorCode.USER_DISABLED,
}


def _translate(error: DBAPIError) -> ApplicationError:
    message = str(error.orig)
    for marker, code in _KNOWN.items():
        if marker in message:
            return ApplicationError(code, message.rsplit(":", 1)[-1].strip())
    raise error


class IdentityRepository:
    """Reads and writes the identity tables for one transaction."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def firm_exists(self) -> bool:
        """Report whether the installation already has its firm."""
        return (await self._session.scalar(select(func.count()).select_from(FirmRow)) or 0) > 0

    async def create_firm(
        self, name: str, jurisdiction: str | None, admin_email: str, admin_display_name: str
    ) -> UUID:
        """Open the firm with its first admin, inside the privileged function."""
        try:
            firm_id = await self._session.scalar(
                text(
                    "select app.create_firm(:name, :jurisdiction, :email, :display_name)"
                ),
                {
                    "name": name,
                    "jurisdiction": jurisdiction,
                    "email": admin_email,
                    "display_name": admin_display_name,
                },
            )
        except DBAPIError as error:
            raise _translate(error) from error
        if firm_id is None:
            raise ApplicationError(ErrorCode.FIRM_EXISTS, "the firm was not created")
        return cast(UUID, firm_id)

    async def find_user_by_email(self, email: str) -> UserRow | None:
        """Find a user by their email, case-insensitively."""
        return await self._session.scalar(
            select(UserRow).where(func.lower(UserRow.email) == email.strip().lower())
        )

    async def add_user(
        self, email: str, display_name: str, status: UserStatus = UserStatus.INVITED
    ) -> UserRow:
        """Insert a user."""
        row = UserRow(email=email, display_name=display_name, status=status.value)
        self._session.add(row)
        await self._session.flush()
        return row

    async def add_membership(
        self, user_id: UUID, firm_id: UUID, role: Role, title: str | None
    ) -> MembershipRow:
        """Insert a membership."""
        row = MembershipRow(user_id=user_id, firm_id=firm_id, role=role.value, title=title)
        self._session.add(row)
        await self._session.flush()
        return row

    async def find_membership(self, user_id: UUID) -> MembershipRow | None:
        """Find a user's single membership."""
        return await self._session.scalar(
            select(MembershipRow).where(MembershipRow.user_id == user_id)
        )

    async def find_user(self, user_id: UUID) -> UserRow | None:
        """Find a user by id."""
        return await self._session.get(UserRow, user_id)

    async def set_role(self, user_id: UUID, role: Role) -> MembershipRow | None:
        """Change a user's role."""
        row = await self.find_membership(user_id)
        if row is not None:
            row.role = role.value
            await self._session.flush()
        return row

    async def disable_user(self, user_id: UUID) -> UserRow | None:
        """Disable a user and their membership, so neither may act."""
        row = await self.find_user(user_id)
        if row is not None:
            row.status = UserStatus.DISABLED.value
        membership = await self.find_membership(user_id)
        if membership is not None:
            membership.disabled_at = func.now()
        await self._session.flush()
        return row

    async def authenticate(self, email: str, password: str) -> AuthIdentity | None:
        """Verify a password inside the database and return the identity it proves."""
        try:
            row = (
                await self._session.execute(
                    text("select user_id, firm_id, role from app.authenticate(:email, :password)"),
                    {"email": email, "password": password},
                )
            ).first()
        except DBAPIError as error:
            raise _translate(error) from error
        if row is None:
            return None
        return AuthIdentity(
            user_id=UserId(row.user_id), firm_id=FirmId(row.firm_id), role=Role(row.role)
        )

    async def create_session(
        self, user_id: UUID, token_hash: str, expires_at: datetime
    ) -> None:
        """Record a session inside the privileged function."""
        await self._session.execute(
            text("select app.create_session(:user_id, :token_hash, :expires_at)"),
            {"user_id": user_id, "token_hash": token_hash, "expires_at": expires_at},
        )

    async def session_actor(self, token_hash: str) -> AuthIdentity | None:
        """Resolve a live session to the identity it acts as."""
        row = (
            await self._session.execute(
                text("select user_id, firm_id from app.session_actor(:token_hash)"),
                {"token_hash": token_hash},
            )
        ).first()
        if row is None:
            return None
        return AuthIdentity(
            user_id=UserId(row.user_id), firm_id=FirmId(row.firm_id), role=Role.STAFF
        )

    async def revoke_session(self, token_hash: str) -> bool:
        """Revoke a session by its token hash."""
        revoked = await self._session.scalar(
            text("select app.revoke_session(:token_hash)"), {"token_hash": token_hash}
        )
        return bool(revoked)
