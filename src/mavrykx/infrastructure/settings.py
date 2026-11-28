"""Typed configuration read once at start-up."""

from __future__ import annotations

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """The runtime configuration, from `MAVRYKX_` environment variables."""

    model_config = SettingsConfigDict(
        env_prefix="MAVRYKX_",
        extra="forbid",
        frozen=True,
        strict=True,
    )

    database_url: SecretStr = Field(
        default=SecretStr("postgresql+asyncpg://maverick_app@localhost:5432/mavrykx"),
        description="The firm database, reached as the non-owner application role.",
    )
    pool_size: int = 5
    pool_timeout_seconds: float = 30.0
