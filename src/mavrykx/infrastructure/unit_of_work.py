"""The SQLAlchemy unit of work, which applies the actor for row-level security."""

from __future__ import annotations

from types import TracebackType
from typing import Self

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from mavrykx.domain.actor import Actor

USER_SETTING = "app.user_id"


def actor_parameters(actor: Actor) -> dict[str, str]:
    """Render the actor as the settings the database policies read.

    An anonymous actor sets an empty value, so `app.current_user()` is null and no policy matches.
    """
    return {"user_id": str(actor.user_id) if actor.user_id is not None else ""}


class SqlAlchemyUnitOfWork:
    """One transaction over one session, with the actor applied before any query runs."""

    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        actor: Actor,
    ) -> None:
        self._session_factory = session_factory
        self._actor = actor
        self._session: AsyncSession | None = None

    @property
    def actor(self) -> Actor:
        """The actor this transaction acts as."""
        return self._actor

    @property
    def session(self) -> AsyncSession:
        """The session repositories use. Private to modules and infrastructure."""
        if self._session is None:
            raise RuntimeError("the unit of work is not entered")
        return self._session

    async def __aenter__(self) -> Self:
        """Open a session and apply the actor to the transaction."""
        self._session = self._session_factory()
        await self._session.execute(
            text("select set_config(:setting, :value, true)"),
            {
                "setting": USER_SETTING,
                "value": actor_parameters(self._actor)["user_id"],
            },
        )
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        """Roll back anything uncommitted and close the session."""
        session = self._session
        self._session = None
        if session is None:
            return
        try:
            await session.rollback()
        finally:
            await session.close()

    async def commit(self) -> None:
        """Persist the work of this transaction."""
        await self.session.commit()

    async def rollback(self) -> None:
        """Discard the work of this transaction."""
        await self.session.rollback()
