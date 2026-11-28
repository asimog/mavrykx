"""Firm, user and membership: the entities this module owns."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import NewType
from uuid import UUID

FirmId = NewType("FirmId", UUID)
UserId = NewType("UserId", UUID)
MembershipId = NewType("MembershipId", UUID)


class Role(StrEnum):
    """The firm role a user holds. One role per user."""

    ADMIN = "admin"
    LAWYER = "lawyer"
    STAFF = "staff"
    INTERN = "intern"


class UserStatus(StrEnum):
    """Where a user is in their working life at the firm."""

    INVITED = "invited"
    ACTIVE = "active"
    SUSPENDED = "suspended"
    DISABLED = "disabled"


@dataclass(frozen=True, slots=True)
class Firm:
    """The organisation this installation serves. There is exactly one."""

    id: FirmId
    name: str
    jurisdiction: str | None
    default_tz: str


@dataclass(frozen=True, slots=True)
class User:
    """One human login and audit actor."""

    id: UserId
    email: str
    display_name: str
    status: UserStatus


@dataclass(frozen=True, slots=True)
class Membership:
    """A user's single role in the firm."""

    id: MembershipId
    user_id: UserId
    firm_id: FirmId
    role: Role
    title: str | None
    disabled_at: datetime | None

    @property
    def is_active(self) -> bool:
        """Report whether this membership may act."""
        return self.disabled_at is None


def may_change_role(actor_role: Role, target_role: Role) -> bool:
    """Only an admin may create or promote another admin."""
    return actor_role is Role.ADMIN or target_role is not Role.ADMIN


@dataclass(frozen=True, slots=True)
class AuthIdentity:
    """The identity a verified credential or a live session proves."""

    user_id: UserId
    firm_id: FirmId
    role: Role
