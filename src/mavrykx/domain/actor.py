"""Who is acting, and on whose behalf."""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID


@dataclass(frozen=True, slots=True)
class Actor:
    """The authenticated human behind one operation.

    A firm user carries both ids. An installation operation, such as the first firm and its
    admin, runs before any user exists and carries neither. The role is not here: it lives on
    the membership row, and the database reads it when a policy needs it.
    """

    user_id: UUID | None = None
    firm_id: UUID | None = None

    @property
    def is_anonymous(self) -> bool:
        """Report whether this operation runs before any user exists."""
        return self.user_id is None
