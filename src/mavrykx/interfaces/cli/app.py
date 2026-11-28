"""Build the Typer application."""

from __future__ import annotations

import typer

from mavrykx.application.system import SystemService
from mavrykx.interfaces.cli import identity as identity_cli
from mavrykx.interfaces.cli import system as system_cli
from mavrykx.modules.identity.api import IdentityService


def build_cli(system_service: SystemService, identity_service: IdentityService) -> typer.Typer:
    """Wire the command groups and the services the composition root provides."""
    app = typer.Typer(help="MavrykX commands.")
    app.add_typer(system_cli.build_system_cli(system_service), name="system")
    app.add_typer(identity_cli.build_identity_cli(identity_service))
    return app
