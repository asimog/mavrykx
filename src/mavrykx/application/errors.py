"""The one failure vocabulary every surface translates."""

from __future__ import annotations

from enum import StrEnum


class ErrorCode(StrEnum):
    """The named failures an operation may raise. The code is the contract, not the message."""

    MATTER_ACCESS_DENIED = "MATTER_ACCESS_DENIED"
    RESOURCE_ACCESS_DENIED = "RESOURCE_ACCESS_DENIED"
    RESOURCE_STALE = "RESOURCE_STALE"
    DOC_STALE_BASE = "DOC_STALE_BASE"
    DOC_STALE_TARGET = "DOC_STALE_TARGET"
    DOC_SESSION_ACTIVE = "DOC_SESSION_ACTIVE"
    DOC_SESSION_REVOKED = "DOC_SESSION_REVOKED"
    EDIT_LEASE_HELD = "EDIT_LEASE_HELD"
    PROPOSAL_STALE = "PROPOSAL_STALE"
    PROPOSAL_CONFLICT = "PROPOSAL_CONFLICT"
    REVIEW_STALE = "REVIEW_STALE"
    RUN_LEASE_LOST = "RUN_LEASE_LOST"
    RUN_ACCESS_REVOKED = "RUN_ACCESS_REVOKED"
    EFFECT_UNCERTAIN = "EFFECT_UNCERTAIN"
    APPROVAL_STALE = "APPROVAL_STALE"
    IDEMPOTENT_REPLAY = "IDEMPOTENT_REPLAY"
    AUTH_INVALID = "AUTH_INVALID"
    USER_DISABLED = "USER_DISABLED"
    SESSION_REVOKED = "SESSION_REVOKED"
    MEMBER_DUPLICATE = "MEMBER_DUPLICATE"
    FIRM_EXISTS = "FIRM_EXISTS"
    USER_EMAIL_TAKEN = "USER_EMAIL_TAKEN"
    USER_NOT_FOUND = "USER_NOT_FOUND"
    ROLE_FORBIDDEN = "ROLE_FORBIDDEN"


class ApplicationError(Exception):
    """A refusal or conflict a service raises, carried unchanged to every surface.

    `retryable` answers whether a durable engine may repeat the call. `effect_uncertain` answers
    whether the effect may already have happened; a crash between the effect and its checkpoint is
    the case the design names `EFFECT_UNCERTAIN`.
    """

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        *,
        retryable: bool = False,
        effect_uncertain: bool = False,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable
        self.effect_uncertain = effect_uncertain

    def __repr__(self) -> str:
        return f"ApplicationError(code={self.code.value!r}, retryable={self.retryable!r})"
