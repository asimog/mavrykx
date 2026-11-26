"""A3: routine comments in production Python and TypeScript."""

from __future__ import annotations

import io
import sys
import tokenize
from collections.abc import Callable, Sequence
from pathlib import Path

from tools.findings import Finding

SCAN_ROOTS = (Path("src"), Path("modules"), Path("tools"), Path("apps/desktop/src"))
PYTHON_SUFFIXES = frozenset({".py"})
TYPESCRIPT_SUFFIXES = frozenset({".ts", ".tsx"})
EXCLUDED_PARTS = frozenset({"node_modules", "out", "dist", "__pycache__", ".venv"})
PYTHON_DIRECTIVES = (
    "#!",
    "# -*-",
    "# coding:",
    "# type:",
    "# noqa",
    "# pragma:",
    "# fmt:",
    "# ruff:",
    "# pyright:",
    "# mypy:",
    "# isort:",
    "# nosec",
    "# coverage:",
    "# SPDX-",
    "# Copyright",
)
TYPESCRIPT_DIRECTIVES = (
    "// eslint-",
    "/* eslint-",
    "// @ts-",
    "// prettier-",
    "// SPDX-",
    "// Copyright",
    "/// <reference",
    "//# sourceMappingURL",
    "/*!",
    "/* @__PURE__",
    "/*#__PURE__",
)
REGEX_PREDECESSORS = frozenset("(,=:[!&|?{};")


def check(root: Path, *, paths: Sequence[Path] | None = None) -> list[Finding]:
    scanned = [_relative(root, path) for path in (paths if paths is not None else _discover(root))]
    findings: list[Finding] = []
    for path in scanned:
        if path.suffix in PYTHON_SUFFIXES:
            comments = _python_comments(root / path)
            allowed: Callable[[int, str], bool] = _python_allowed
        elif path.suffix in TYPESCRIPT_SUFFIXES:
            comments = _typescript_comments((root / path).read_text(encoding="utf-8"))
            allowed = _typescript_allowed
        else:
            continue
        for line, text in comments:
            if allowed(line, text):
                continue
            findings.append(
                Finding(
                    "A3",
                    path,
                    line,
                    "routine comment",
                    "rename, extract, or write a test; use a docstring for the abstraction",
                )
            )
    return findings


def _relative(root: Path, path: Path) -> Path:
    return path.relative_to(root) if path.is_absolute() else path


def _discover(root: Path) -> list[Path]:
    suffixes = PYTHON_SUFFIXES | TYPESCRIPT_SUFFIXES
    files: list[Path] = []
    for base in SCAN_ROOTS:
        directory = root / base
        if not directory.exists():
            continue
        for path in directory.rglob("*"):
            if path.suffix in suffixes and not EXCLUDED_PARTS.intersection(path.parts):
                files.append(path.relative_to(root))
    return sorted(files)


def _python_comments(path: Path) -> list[tuple[int, str]]:
    source = path.read_text(encoding="utf-8")
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except tokenize.TokenError as error:
        raise RuntimeError(f"{path}: cannot read comments: {error}") from error
    return [
        (token.start[0], token.string) for token in tokens if token.type == tokenize.COMMENT
    ]


def _python_allowed(line: int, text: str) -> bool:
    stripped = text.strip()
    if stripped.startswith(PYTHON_DIRECTIVES):
        return True
    return line <= 10 and ("Copyright" in stripped or "SPDX-License-Identifier" in stripped)


def _typescript_allowed(line: int, text: str) -> bool:
    del line
    stripped = text.strip()
    if stripped.startswith(TYPESCRIPT_DIRECTIVES):
        return True
    return "Copyright" in stripped or "SPDX-License-Identifier" in stripped


def _typescript_comments(source: str) -> list[tuple[int, str]]:
    comments: list[tuple[int, str]] = []
    index = 0
    line = 1
    previous = ""
    length = len(source)

    while index < length:
        character = source[index]
        if character == "\n":
            line += 1
            index += 1
            continue
        if character in "'\"`":
            quote = character
            index += 1
            while index < length:
                if source[index] == "\\":
                    index += 2
                    continue
                if source[index] == quote:
                    index += 1
                    break
                if source[index] == "\n":
                    line += 1
                index += 1
            previous = "x"
            continue
        if character == "/" and index + 1 < length and source[index + 1] == "/":
            start = index
            while index < length and source[index] != "\n":
                index += 1
            comments.append((line, source[start:index]))
            continue
        if character == "/" and index + 1 < length and source[index + 1] == "*":
            start = index
            start_line = line
            index += 2
            while index + 1 < length and not (source[index] == "*" and source[index + 1] == "/"):
                if source[index] == "\n":
                    line += 1
                index += 1
            index = min(index + 2, length)
            comments.append((start_line, source[start:index]))
            continue
        if character == "/" and previous in REGEX_PREDECESSORS:
            index += 1
            in_class = False
            while index < length:
                current = source[index]
                if current == "\\":
                    index += 2
                    continue
                if current == "[":
                    in_class = True
                elif current == "]":
                    in_class = False
                elif current == "/" and not in_class:
                    index += 1
                    break
                elif current == "\n":
                    break
                index += 1
            previous = "x"
            continue
        if not character.isspace():
            previous = character
        index += 1

    return comments


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    root = Path(arguments[0]) if arguments else Path.cwd()
    findings = check(root)
    for finding in findings:
        print(finding.render())
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
