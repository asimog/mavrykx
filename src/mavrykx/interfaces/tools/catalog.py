"""The tool catalog: the agent-facing subset of the registry."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from pydantic import BaseModel

from mavrykx.interfaces.tools.context import ToolContext
from mavrykx.interfaces.tools.system import system_status


@dataclass(frozen=True, slots=True)
class ToolEntry:
    operation_id: str
    function: Callable[[ToolContext], BaseModel]


TOOLS: tuple[ToolEntry, ...] = (
    ToolEntry("system.status", system_status),
)
