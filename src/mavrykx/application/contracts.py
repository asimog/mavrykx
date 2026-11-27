"""Contracts at the application boundary."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class _Contract(BaseModel):
    """A strict boundary model: frozen, no unknown fields, no coercion."""

    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)


class SystemStatusInput(_Contract):
    """The empty request for system.status."""


class SystemStatus(_Contract):
    """The running build, as every surface reports it."""

    name: str
    version: str
