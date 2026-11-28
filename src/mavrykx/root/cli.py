"""The composition root for the CLI."""

from __future__ import annotations

from mavrykx.application.system import SystemService
from mavrykx.infrastructure.settings import Settings
from mavrykx.interfaces.cli.app import build_cli
from mavrykx.modules.identity.api import IdentityService
from mavrykx.root.runtime import Runtime

runtime = Runtime(Settings())

cli = build_cli(SystemService(), IdentityService(runtime.unit_of_work))


def main() -> None:
    """Run the CLI."""
    cli()
