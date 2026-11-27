"""Build the Typer application."""

from __future__ import annotations

import typer

from mavrykx.application.system import SystemService
from mavrykx.interfaces.cli import system


def build_cli(service: SystemService) -> typer.Typer:
    app = typer.Typer(help="MavrykX commands.")
    app.add_typer(system.build_system_cli(service), name="system")
    return app
