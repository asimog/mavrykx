"""The composition root for the CLI."""

from __future__ import annotations

from mavrykx.application.system import SystemService
from mavrykx.interfaces.cli.app import build_cli

cli = build_cli(SystemService())


def main() -> None:
    cli()
