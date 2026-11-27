"""B2, B3 and D2: the registry, the surfaces and interface decisions."""

from __future__ import annotations

import ast
from collections.abc import Iterable, Sequence
from pathlib import Path

from fastapi import FastAPI
from typer import Typer

from mavrykx.application.registry import OPERATIONS, Operation
from mavrykx.application.system import SystemService
from mavrykx.interfaces.api.app import build_app
from mavrykx.interfaces.cli.app import build_cli
from mavrykx.interfaces.tools.catalog import TOOLS, ToolEntry
from tools.findings import Finding

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / "src" / "mavrykx" / "interfaces"
BANNED = (ast.If, ast.Match, ast.For, ast.While, ast.Try)


def check() -> list[Finding]:
    findings = check_parity(
        OPERATIONS, build_app(SystemService()), build_cli(SystemService()), TOOLS
    )
    findings.extend(check_branches([INTERFACES]))
    return findings


def check_parity(
    operations: Sequence[Operation],
    api: FastAPI,
    cli: Typer,
    tools: Sequence[ToolEntry],
) -> list[Finding]:
    findings: list[Finding] = []
    registry = {operation.id: operation for operation in operations}
    http = _http_ids(api)
    commands = _command_ids(cli)
    tool_ids = {entry.operation_id for entry in tools}

    for operation in operations:
        actual: set[str] = set()
        if operation.id in http:
            actual.add("http")
        if operation.id in commands:
            actual.add("cli")
        if operation.id in tool_ids:
            actual.add("tool")
        expected = set(operation.surfaces)
        if actual != expected:
            findings.append(
                Finding(
                    "B3",
                    Path("src/mavrykx/application/registry.py"),
                    None,
                    f"{operation.id} declares {sorted(expected)} but serves {sorted(actual)}",
                    "add the missing surface adapter or remove the surface from the registry",
                )
            )
        if operation.human_only and "tool" in actual:
            findings.append(
                Finding(
                    "D2",
                    Path("src/mavrykx/interfaces/tools/catalog.py"),
                    None,
                    f"{operation.id} is human-only but has a tool",
                    "remove the tool; a prompt injection must not reach a human-only action",
                )
            )

    for surface, ids in (("http", http), ("cli", commands), ("tool", tool_ids)):
        for missing in sorted(ids - set(registry)):
            findings.append(
                Finding(
                    "B3",
                    INTERFACES.relative_to(ROOT),
                    None,
                    f"{surface} surface {missing} has no registry entry",
                    "add the operation to the registry or remove the adapter",
                )
            )
    return findings


def check_branches(paths: Iterable[Path]) -> list[Finding]:
    findings: list[Finding] = []
    for path in _python_files(paths):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, BANNED):
                findings.append(
                    Finding(
                        "B2",
                        _relative(path),
                        node.lineno,
                        "decision in an interface",
                        "move the branch into the application service",
                    )
                )
    return findings


def _http_ids(api: FastAPI) -> set[str]:
    ids: set[str] = set()
    for path_item in api.openapi().get("paths", {}).values():
        for operation in path_item.values():
            if isinstance(operation, dict) and "operationId" in operation:
                ids.add(str(operation["operationId"]))
    return ids


def _command_ids(app: Typer, prefix: str = "") -> set[str]:
    ids: set[str] = set()
    for command in app.registered_commands:
        name = command.name or getattr(command.callback, "__name__", None)
        if name is not None:
            ids.add(f"{prefix}.{name}" if prefix else name)
    for group in app.registered_groups:
        if group.name is None or group.typer_instance is None:
            continue
        child_prefix = f"{prefix}.{group.name}" if prefix else group.name
        ids |= _command_ids(group.typer_instance, child_prefix)
    return ids


def _python_files(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_file() and path.suffix == ".py":
            yield path
        elif path.is_dir():
            yield from path.rglob("*.py")


def _relative(path: Path) -> Path:
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


def main() -> int:
    findings = check()
    for finding in findings:
        print(finding.render())
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
