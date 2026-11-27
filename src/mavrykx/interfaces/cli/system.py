"""The system CLI surface."""

from __future__ import annotations

import typer

from mavrykx.application.system import SystemService


def build_system_cli(service: SystemService) -> typer.Typer:
    app = typer.Typer(help="System commands.")

    @app.command("status")
    def status() -> None:
        typer.echo(service.status().model_dump_json())

    return app
