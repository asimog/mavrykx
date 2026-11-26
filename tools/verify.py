"""The one verification command for MavrykX."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from tools import comments, markdown_policy, negative, schema
from tools.errors import ToolMissing
from tools.findings import Finding, render_all

ROOT = Path(__file__).resolve().parents[1]
NODE_VERSION_FILE = ROOT / ".node-version"
UV_VERSION = "0.13.10"
FAST_BUDGET_SECONDS = 30.0


@dataclass(frozen=True, slots=True)
class Check:
    label: str
    rules: tuple[str, ...]
    fast: bool
    run: Callable[[], tuple[bool, str]]


def _markdown() -> tuple[bool, str]:
    return _from_findings(markdown_policy.check(ROOT))


def _comments() -> tuple[bool, str]:
    return _from_findings(comments.check(ROOT))


def _ruff() -> tuple[bool, str]:
    return _command([_python_tool("ruff"), "check", "--output-format", "concise", "."])


def _mypy() -> tuple[bool, str]:
    return _command([_python_tool("mypy")])


def _eslint() -> tuple[bool, str]:
    return _command([*_node_script("eslint/bin/eslint.js"), "."])


def _tsc() -> tuple[bool, str]:
    node = _node()
    script = ROOT / "node_modules" / "typescript" / "bin" / "tsc"
    if not script.exists():
        raise ToolMissing("typescript is not installed; run npm ci")
    results = [
        _command([node, str(script), "--noEmit", "-p", "apps/desktop/tsconfig.node.json"]),
        _command([node, str(script), "--noEmit", "-p", "apps/desktop/tsconfig.web.json"]),
    ]
    ok = all(result[0] for result in results)
    return ok, "\n".join(detail for _, detail in results if detail)


def _import_linter() -> tuple[bool, str]:
    return _command([_python_tool("lint-imports")])


def _depcruise() -> tuple[bool, str]:
    return _command(
        [*_node_script("dependency-cruiser/bin/dependency-cruiser.mjs"), "apps/desktop/src"]
    )


def _pytest() -> tuple[bool, str]:
    return _command([sys.executable, "-m", "pytest"])


def _negative() -> tuple[bool, str]:
    results = negative.run()
    lines: list[str] = []
    failed = False
    for title, ok, detail in results:
        lines.append(f"{'✓' if ok else '✗'} {title}")
        if not ok:
            failed = True
            if detail:
                lines.append(_indent(detail))
    return not failed, "\n".join(lines)


def _audit() -> tuple[bool, str]:
    pip_ok, pip_output = _command([sys.executable, "-m", "pip_audit", "--skip-editable"])
    npm_ok, npm_output = _command(_npm_argv("audit", "--audit-level=high"))
    return pip_ok and npm_ok, "\n".join(part for part in (pip_output, npm_output) if part)


def _lock_check() -> tuple[bool, str]:
    uv = shutil.which("uv")
    if uv is None:
        raise ToolMissing("uv is not installed; install uv 0.13.10")
    return _command([uv, "lock", "--check"])


def _schema() -> tuple[bool, str]:
    return _from_findings(schema.check())


CHECKS: tuple[Check, ...] = (
    Check("C1-C3 Markdown policy", ("C1", "C2", "C3"), True, _markdown),
    Check("A3   Comment policy", ("A3",), True, _comments),
    Check("A1   Python types", ("A1",), True, _mypy),
    Check("A1   TypeScript types", ("A1",), True, _tsc),
    Check("A2/A4 Ruff", ("A2", "A4"), True, _ruff),
    Check("A2/A5 ESLint", ("A2", "A5"), True, _eslint),
    Check("B1/B6 Python layers", ("B1", "B6"), True, _import_linter),
    Check("B4/B6 Renderer isolation", ("B4", "B6"), True, _depcruise),
    Check("T    Unit tests", ("T",), False, _pytest),
    Check("N    Negative fixtures", ("N",), False, _negative),
    Check("A6   Dependency audit", ("A6",), False, _audit),
    Check("L    Lockfile current", ("L",), False, _lock_check),
    Check("E8   Schema drift", ("E8",), False, _schema),
)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m tools.verify",
        description="Run MavrykX's verification rules.",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--fast",
        action="store_true",
        help="edit loop: docs, lint, types, boundaries",
    )
    mode.add_argument("--full", action="store_true", help="fast plus tests, negatives and audits")
    mode.add_argument("--rule", metavar="ID", help="one rule and its negative fixture")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    _utf8()
    arguments = _parser().parse_args(argv)
    problems = _toolchain(full=arguments.full)
    if problems:
        for problem in problems:
            print(f"R0: {problem}")
        return 1

    checks = _select(arguments)
    started = time.perf_counter()
    failures = 0
    for check in checks:
        check_started = time.perf_counter()
        try:
            ok, detail = check.run()
        except (ToolMissing, RuntimeError, SyntaxError, ValueError) as error:
            ok, detail = False, f"R0: {error}"
        elapsed = time.perf_counter() - check_started
        print(f"{'✓' if ok else '✗'} {check.label:<30} {elapsed:5.1f}s")
        if not ok:
            failures += 1
            if detail:
                print(_indent(detail))

    if arguments.rule is not None:
        for title, ok, detail in negative.run(arguments.rule.upper()):
            print(f"{'✓' if ok else '✗'} {title}")
            if not ok:
                failures += 1
                if detail:
                    print(_indent(detail))

    total = time.perf_counter() - started
    status = "PASS" if failures == 0 else "FAIL"
    print(f"\n{status} — {len(checks)} checks in {total:.1f}s")
    if arguments.fast and total > FAST_BUDGET_SECONDS:
        print(f"warning: --fast took {total:.1f}s; the budget is {FAST_BUDGET_SECONDS:.0f}s")
    return 0 if failures == 0 else 1


def _select(arguments: argparse.Namespace) -> list[Check]:
    if arguments.rule is not None:
        rule = arguments.rule.upper()
        selected = [check for check in CHECKS if rule in check.rules]
        if not selected:
            raise SystemExit(f"unknown rule: {rule}")
        return selected
    return [check for check in CHECKS if check.fast or arguments.full]


def _toolchain(*, full: bool) -> list[str]:
    problems: list[str] = []
    if sys.version_info[:2] != (3, 14):
        problems.append(f"Python 3.14 is required; found {sys.version.split()[0]}")

    uv = shutil.which("uv")
    if uv is None:
        problems.append(f"uv {UV_VERSION} is required; not found")
    else:
        code, output = _run([uv, "--version"])
        if code != 0 or not output.startswith(f"uv {UV_VERSION}"):
            problems.append(f"uv {UV_VERSION} is required; found {output or 'unknown'}")

    wanted = ""
    if NODE_VERSION_FILE.exists():
        wanted = NODE_VERSION_FILE.read_text(encoding="utf-8").strip()
    node = shutil.which("node")
    if node is None:
        problems.append(f"Node {wanted or '26.13.1'} is required; not found")
    elif wanted:
        code, output = _run([node, "--version"])
        actual = output.strip().removeprefix("v")
        if actual != wanted:
            message = f"Node {wanted} is required; found {actual}"
            if full:
                problems.append(message)
            else:
                print(f"warning: {message} — --fast continues, --full fails")
    return problems


def _from_findings(findings: list[Finding]) -> tuple[bool, str]:
    return not findings, render_all(findings)


def _python_tool(name: str) -> str:
    suffix = ".exe" if os.name == "nt" else ""
    candidate = Path(sys.executable).parent / f"{name}{suffix}"
    if candidate.exists():
        return str(candidate)
    found = shutil.which(name)
    if found is None:
        raise ToolMissing(f"{name} is not installed; run uv sync")
    return found


def _node() -> str:
    found = shutil.which("node")
    if found is None:
        raise ToolMissing("node is not installed; install Node 26.13.1 and run npm ci")
    return found


def _node_script(relative: str) -> list[str]:
    script = ROOT / "node_modules" / relative
    if not script.exists():
        raise ToolMissing(f"node_modules/{relative} is not installed; run npm ci")
    return [_node(), str(script)]


def _npm_argv(*arguments: str) -> list[str]:
    npm = shutil.which("npm")
    if npm is None:
        raise ToolMissing("npm is not installed; install Node 26.13.1")
    if os.name == "nt":
        return ["cmd", "/d", "/c", npm, *arguments]
    return [npm, *arguments]


def _command(argv: Sequence[str]) -> tuple[bool, str]:
    code, output = _run(argv)
    return code == 0, output


def _run(argv: Sequence[str], env: Mapping[str, str] | None = None) -> tuple[int, str]:
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=dict(env) if env is not None else _environment(),
        check=False,
    )
    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part).strip()
    return completed.returncode, output


def _environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment["NO_COLOR"] = "1"
    environment["FORCE_COLOR"] = "0"
    environment["PYTHONIOENCODING"] = "utf-8"
    environment["PYTHONUTF8"] = "1"
    return environment


def _indent(text: str, prefix: str = "    ") -> str:
    return "\n".join(prefix + line for line in text.splitlines())


def _utf8() -> None:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
