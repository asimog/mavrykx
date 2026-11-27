"""The negative suite: every rule must fail its fixture for the right reason."""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from tools import comments, markdown_policy, operations
from tools.errors import ToolMissing

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "negative"


@dataclass(frozen=True, slots=True)
class NegativeCase:
    rule: str
    title: str
    kind: str
    target: str
    allowlist: tuple[tuple[str, str], ...] = ()


CASES: tuple[NegativeCase, ...] = (
    NegativeCase("C1", "unlisted Markdown fails", "markdown", "markdown/UNLISTED.md"),
    NegativeCase(
        "C2",
        "a FINAL filename fails",
        "markdown",
        "markdown/FINAL-architecture.md",
        (("markdown/FINAL-architecture.md", "fixture"),),
    ),
    NegativeCase(
        "C3",
        "a duplicate title fails",
        "markdown",
        "markdown/duplicate",
        (("markdown/duplicate/a.md", "fixture"), ("markdown/duplicate/b.md", "fixture")),
    ),
    NegativeCase("A3", "a routine Python comment fails", "comments", "routine_comment.py"),
    NegativeCase("A3", "a routine TypeScript comment fails", "comments", "routine_comment.ts"),
    NegativeCase(
        "B1",
        "domain importing SQLAlchemy fails",
        "lint-imports",
        "importlinter.domain.ini",
    ),
    NegativeCase("B6", "a cycle fails", "lint-imports", "importlinter.cycles.ini"),
    NegativeCase("B4", "a renderer importing Node fails", "depcruise", "renderer_fs.ts"),
    NegativeCase(
        "B2",
        "a decision in an interface fails",
        "operations-branch",
        "operations/route_decision.py",
    ),
    NegativeCase("B3", "a route outside the registry fails", "operations-parity", "extra"),
    NegativeCase("D2", "a human-only tool fails", "operations-parity", "human"),
)


def run(rule: str | None = None) -> list[tuple[str, bool, str]]:
    results: list[tuple[str, bool, str]] = []
    for case in CASES:
        if rule is not None and case.rule != rule:
            continue
        ok, detail = _execute(case)
        results.append((f"{case.rule} negative: {case.title}", ok, detail))
    return results


def _execute(case: NegativeCase) -> tuple[bool, str]:
    try:
        if case.kind == "markdown":
            return _markdown(case)
        if case.kind == "comments":
            return _comments(case)
        if case.kind == "lint-imports":
            return _lint_imports(FIXTURES / case.target, case.rule)
        if case.kind == "depcruise":
            return _depcruise(FIXTURES / case.target)
        if case.kind == "operations-branch":
            return _operations_branch(case)
        if case.kind == "operations-parity":
            return _operations_parity(case)
    except ToolMissing as error:
        return False, str(error)
    raise ValueError(f"unknown negative case kind: {case.kind}")


def _markdown(case: NegativeCase) -> tuple[bool, str]:
    target = FIXTURES / case.target
    paths = [target] if target.is_file() else sorted(target.glob("*.md"))
    findings = markdown_policy.check(
        FIXTURES,
        paths=paths,
        allowlist=dict(case.allowlist),
    )
    rules = {finding.rule for finding in findings}
    return rules == {case.rule}, "\n".join(finding.render() for finding in findings)


def _comments(case: NegativeCase) -> tuple[bool, str]:
    findings = comments.check(FIXTURES, paths=[FIXTURES / case.target])
    rules = {finding.rule for finding in findings}
    return rules == {case.rule}, "\n".join(finding.render() for finding in findings)


def _operations_branch(case: NegativeCase) -> tuple[bool, str]:
    findings = operations.check_branches([FIXTURES / case.target])
    rules = {finding.rule for finding in findings}
    return rules == {case.rule}, "\n".join(finding.render() for finding in findings)


def _operations_parity(case: NegativeCase) -> tuple[bool, str]:
    module = _fixture_module()
    if case.target == "extra":
        findings = operations.check_parity(module.VALID, module.extra_api(), module.empty_cli(), ())
    else:
        findings = operations.check_parity(
            module.HUMAN, module.empty_api(), module.empty_cli(), module.human_tools()
        )
    rules = {finding.rule for finding in findings}
    return rules == {case.rule}, "\n".join(finding.render() for finding in findings)


def _fixture_module() -> ModuleType:
    path = FIXTURES / "operations" / "fixtures.py"
    spec = importlib.util.spec_from_file_location("operations_fixtures", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _lint_imports(config: Path, expected: str) -> tuple[bool, str]:
    environment = os.environ.copy()
    environment["PYTHONPATH"] = str(FIXTURES) + os.pathsep + environment.get("PYTHONPATH", "")
    code, output = _run([_python_binary("lint-imports"), "--config", str(config)], environment)
    return code != 0 and expected in output, output


def _depcruise(target: Path) -> tuple[bool, str]:
    node = shutil.which("node")
    if node is None:
        raise ToolMissing("node is not installed; install Node 26.13.1 and run npm ci")
    script = ROOT / "node_modules" / "dependency-cruiser" / "bin" / "dependency-cruiser.mjs"
    if not script.exists():
        raise ToolMissing("dependency-cruiser is not installed; run npm ci")
    code, output = _run(
        [
            node,
            str(script),
            "--config",
            str(FIXTURES / "depcruise.negative.cjs"),
            str(target),
        ],
        os.environ.copy(),
    )
    return code != 0 and "B4" in output, output


def _python_binary(name: str) -> str:
    suffix = ".exe" if os.name == "nt" else ""
    candidate = Path(sys.executable).parent / f"{name}{suffix}"
    if candidate.exists():
        return str(candidate)
    found = shutil.which(name)
    if found is None:
        raise ToolMissing(f"{name} is not installed; run uv sync")
    return found


def _run(argv: Sequence[str], environment: dict[str, str]) -> tuple[int, str]:
    environment = dict(environment)
    environment["NO_COLOR"] = "1"
    environment["FORCE_COLOR"] = "0"
    environment["PYTHONIOENCODING"] = "utf-8"
    environment["PYTHONUTF8"] = "1"
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=environment,
        check=False,
    )
    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part).strip()
    return completed.returncode, output
