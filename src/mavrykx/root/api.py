"""The composition root for the HTTP surface."""

from __future__ import annotations

from mavrykx.application.system import SystemService
from mavrykx.infrastructure.settings import Settings
from mavrykx.interfaces.api.app import build_app
from mavrykx.modules.identity.api import IdentityService
from mavrykx.root.runtime import Runtime

runtime = Runtime(Settings())

app = build_app(SystemService(), IdentityService(runtime.unit_of_work))


def main() -> None:
    """Start the HTTP surface.

    Raises:
        NotImplementedError: an ASGI server is not a declared dependency yet.
    """
    raise NotImplementedError(
        "mavrykx-api needs an ASGI server; add uvicorn and serve mavrykx.root.api:app"
    )
