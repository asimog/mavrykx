"""The system status use case."""

from __future__ import annotations

from mavrykx import __version__
from mavrykx.application.contracts import SystemStatus


class SystemService:
    """Reports the running build. It owns no legal record and needs no Matter scope."""

    def status(self) -> SystemStatus:
        return SystemStatus(name="MavrykX", version=__version__)
