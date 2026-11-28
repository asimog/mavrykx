"""The one definition of each business action."""

from __future__ import annotations

from collections.abc import Callable
from typing import Literal

from pydantic import BaseModel, ConfigDict

from mavrykx.application.contracts import SystemStatus, SystemStatusInput
from mavrykx.application.system import SystemService

Surface = Literal["cli", "http", "tool"]
DEFAULT_SURFACES: frozenset[Surface] = frozenset({"cli", "http", "tool"})


class Operation(BaseModel):
    """One business action: its contracts, its call and the surfaces that serve it.

    The registry is the single declaration. Each surface is bound to it by `id`, and
    `tools/operations.py` fails when the three projections disagree with this list.
    """

    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)

    id: str
    summary: str
    input_model: type[BaseModel]
    output_model: type[BaseModel]
    call: Callable[[BaseModel], BaseModel] | None = None
    surfaces: frozenset[Surface] = DEFAULT_SURFACES
    human_only: bool = False


def _status(_request: BaseModel) -> BaseModel:
    return SystemService().status()


OPERATIONS: tuple[Operation, ...] = (
    Operation(
        id="system.status",
        summary="Report the running MavrykX version.",
        input_model=SystemStatusInput,
        output_model=SystemStatus,
        call=_status,
    ),
)
"""The operations the application layer itself owns. Module operations are added in composition."""
