"""The database engine and session factory."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from mavrykx.infrastructure.settings import Settings


def build_engine(settings: Settings) -> AsyncEngine:
    """Create the one engine for this process."""
    return create_async_engine(
        settings.database_url.get_secret_value(),
        pool_size=settings.pool_size,
        pool_timeout=settings.pool_timeout_seconds,
        pool_pre_ping=True,
    )


def build_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    """Create the session factory the unit of work takes."""
    return async_sessionmaker(engine, expire_on_commit=False)
