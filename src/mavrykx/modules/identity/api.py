"""The public surface of the identity module.

Other modules import from here, never from `models`, `repository` or `internal`.
"""

from __future__ import annotations

from typing import Literal

from mavrykx.application.registry import Operation
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
from mavrykx.modules.identity.domain import (
    Firm,
    FirmId,
    Membership,
    MembershipId,
    Role,
    User,
    UserId,
    UserStatus,
)
from mavrykx.modules.identity.service import IdentityService

IDENTITY_SURFACES: frozenset[Literal["cli", "http", "tool"]] = frozenset({"cli", "http"})

OPERATIONS: tuple[Operation, ...] = (
    Operation(
        id="firm.init",
        summary="Open the installation with its firm and first admin.",
        input_model=FirmInitRequest,
        output_model=FirmView,
        surfaces=IDENTITY_SURFACES,
    ),
    Operation(
        id="user.invite",
        summary="Invite a user and give them their role.",
        input_model=UserInviteRequest,
        output_model=UserView,
        surfaces=IDENTITY_SURFACES,
    ),
    Operation(
        id="user.disable",
        summary="Disable a user; their sessions stop working.",
        input_model=UserDisableRequest,
        output_model=UserView,
        surfaces=IDENTITY_SURFACES,
    ),
    Operation(
        id="membership.set_role",
        summary="Change a user's firm role.",
        input_model=MembershipSetRoleRequest,
        output_model=MembershipView,
        surfaces=IDENTITY_SURFACES,
    ),
    Operation(
        id="session.create",
        summary="Sign in and mint a session token.",
        input_model=SessionCreateRequest,
        output_model=SessionView,
        surfaces=IDENTITY_SURFACES,
    ),
    Operation(
        id="session.revoke",
        summary="Revoke a session.",
        input_model=SessionRevokeRequest,
        output_model=SessionRevoked,
        surfaces=IDENTITY_SURFACES,
    ),
)

__all__ = [
    "OPERATIONS",
    "Firm",
    "FirmId",
    "FirmInitRequest",
    "FirmView",
    "IdentityService",
    "Membership",
    "MembershipId",
    "MembershipSetRoleRequest",
    "MembershipView",
    "Role",
    "SessionCreateRequest",
    "SessionRevokeRequest",
    "SessionRevoked",
    "SessionView",
    "User",
    "UserDisableRequest",
    "UserId",
    "UserInviteRequest",
    "UserStatus",
    "UserView",
]
