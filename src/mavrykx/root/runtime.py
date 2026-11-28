"""The only place the database runtime is constructed."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from mavrykx.domain.actor import Actor
from mavrykx.infrastructure.database import build_engine, build_session_factory
from mavrykx.infrastructure.settings import Settings
from mavrykx.infrastructure.unit_of_work import SqlAlchemyUnitOfWork


class Runtime:
    """The process-wide database runtime: one engine, one session factory."""

    def __init__(self, settings: Settings) -> None:
        self._engine = build_engine(settings)
        self._session_factory = build_session_factory(self._engine)

    @property
    def engine(self) -> AsyncEngine:
        """The engine this process owns."""
        return self._engine

    @property
    def session_factory(self) -> async_sessionmaker[AsyncSession]:
        """The session factory, for code that must open its own session."""
        return self._session_factory

    def unit_of_work(self, actor: Actor) -> SqlAlchemyUnitOfWork:
        """Open one transaction as one actor."""
        return SqlAlchemyUnitOfWork(self._session_factory, actor)

    async def dispose(self) -> None:
        """Release the pool on shutdown."""
        await self._engine.dispose()
