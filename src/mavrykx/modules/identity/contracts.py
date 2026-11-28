"""The boundary contracts of the identity module."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from mavrykx.modules.identity.domain import Role, UserStatus


class _Contract(BaseModel):
    """A strict boundary model: frozen, no unknown fields, no coercion."""

    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)


class FirmInitRequest(_Contract):
    """Open the installation: the firm and its first admin."""

    firm_name: str = Field(min_length=1, max_length=200)
    jurisdiction: str | None = None
    admin_email: EmailStr
    admin_display_name: str = Field(min_length=1, max_length=200)


class FirmView(_Contract):
    """The firm as the surfaces report it."""

    id: UUID
    name: str
    jurisdiction: str | None
    default_tz: str


class UserInviteRequest(_Contract):
    """Invite a user and give them their one role."""

    email: EmailStr
    display_name: str = Field(min_length=1, max_length=200)
    role: Role
    title: str | None = None


class UserView(_Contract):
    """A user and their role."""

    id: UUID
    email: str
    display_name: str
    status: UserStatus
    role: Role


class UserDisableRequest(_Contract):
    """Disable a user; their sessions stop working."""

    user_id: UUID


class MembershipSetRoleRequest(_Contract):
    """Change a user's role."""

    user_id: UUID
    role: Role


class MembershipView(_Contract):
    """A membership as the surfaces report it."""

    user_id: UUID
    role: Role
    title: str | None
    disabled_at: datetime | None


class SessionCreateRequest(_Contract):
    """Sign in with an email and a password."""

    email: EmailStr
    password: str = Field(min_length=1, max_length=200)


class SessionView(_Contract):
    """A live session. The token is returned once and never stored in clear."""

    token: str
    expires_at: datetime
    user_id: UUID
    firm_id: UUID
    role: Role


class SessionRevokeRequest(_Contract):
    """Revoke a session by its token."""

    token: str = Field(min_length=1, max_length=200)


class SessionRevoked(_Contract):
    """The result of revoking a session."""

    revoked: bool
