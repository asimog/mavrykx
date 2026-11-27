"""The system.status tool adapter."""

from __future__ import annotations

from mavrykx.application.contracts import SystemStatus
from mavrykx.interfaces.tools.context import ToolContext


def system_status(context: ToolContext) -> SystemStatus:
    return SystemStatus.model_validate(context.gateway.call("system.status", {}))
