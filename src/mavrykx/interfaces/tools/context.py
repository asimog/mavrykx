"""The dependencies a tool adapter receives."""

from __future__ import annotations

from dataclasses import dataclass

from mavrykx.gateway.service import ToolGateway


@dataclass(frozen=True, slots=True)
class ToolContext:
    gateway: ToolGateway
