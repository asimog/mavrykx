"""The transaction boundary every application service works inside."""

from __future__ import annotations

from types import TracebackType
from typing import Protocol, Self

from mavrykx.domain.actor import Actor


class UnitOfWork(Protocol):
    """One transaction, scoped to one actor, committed by the service that owns the use case.

    Entering it sets the actor for row-level security. Leaving it without a commit rolls back, so a
    service that raises leaves no partial state.
    """

    @property
    def actor(self) -> Actor:
        """The actor this transaction acts as."""
        ...

    async def __aenter__(self) -> Self:
        """Start the transaction and apply the actor."""
        ...

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        """Close the transaction, rolling back anything uncommitted."""
        ...

    async def commit(self) -> None:
        """Persist the unit of work."""
        ...

    async def rollback(self) -> None:
        """Discard the unit of work."""
        ...
