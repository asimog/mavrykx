"""C1-C3: the set of Markdown files, their names and their titles."""

from __future__ import annotations

import re
import subprocess
import sys
import tomllib
from collections.abc import Mapping, Sequence
from pathlib import Path

from tools.findings import Finding

DEFAULT_ALLOWLIST = Path(__file__).with_name("markdown_allowlist.toml")
EXCLUDED_PREFIXES = (
    ".agents/",
    ".opencode/",
    ".venv/",
    "node_modules/",
    "tests/negative/",
    "vendor/",
)
BANNED_NAME = re.compile(r"(?i)(?:^|[-_. ])(final|updated|new|v2|copy|old|backup)(?:[-_. ]|$)")


def load_allowlist(path: Path = DEFAULT_ALLOWLIST) -> dict[str, str]:
    with path.open("rb") as handle:
        data = tomllib.load(handle)
    entries: dict[str, str] = {}
    for item in data.get("file", []):
        if not isinstance(item, dict):
            raise TypeError(f"{path}: each [[file]] entry must be a table")
        name = item.get("path")
        reason = item.get("reason", "")
        if not isinstance(name, str) or not isinstance(reason, str):
            raise TypeError(f"{path}: path and reason must be strings")
        entries[name] = reason
    return entries


def tracked_markdown(root: Path) -> list[Path]:
    completed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.md"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"git ls-files failed: {completed.stderr.strip()}")
    paths = (Path(line) for line in completed.stdout.splitlines() if line)
    return sorted(
        path for path in paths if not path.as_posix().startswith(EXCLUDED_PREFIXES)
    )


def check(
    root: Path,
    *,
    paths: Sequence[Path] | None = None,
    allowlist: Mapping[str, str] | None = None,
) -> list[Finding]:
    selected = paths if paths is not None else tracked_markdown(root)
    scanned = [_relative(root, path) for path in selected]
    allowed = dict(allowlist) if allowlist is not None else load_allowlist()
    findings: list[Finding] = []
    present: set[str] = set()

    for path in scanned:
        name = path.as_posix()
        present.add(name)
        if name not in allowed:
            findings.append(
                Finding(
                    "C1",
                    path,
                    None,
                    "unapproved Markdown file",
                    "add it to tools/markdown_allowlist.toml with a reason, or update its owner",
                )
            )
            continue
        if not allowed[name].strip():
            findings.append(
                Finding(
                    "C1",
                    path,
                    None,
                    "allowlist entry has no reason",
                    "state why this file exists in tools/markdown_allowlist.toml",
                )
            )
        if BANNED_NAME.search(path.stem):
            findings.append(
                Finding(
                    "C2",
                    path,
                    None,
                    "temporary or versioned filename",
                    "rename the file and update its owner",
                )
            )
        title = _title(root / path)
        if title is not None and BANNED_NAME.search(title):
            findings.append(
                Finding(
                    "C2",
                    path,
                    1,
                    f"temporary or versioned heading: {title}",
                    "rename the heading and update its owner",
                )
            )

    for missing in sorted(set(allowed) - present):
        findings.append(
            Finding(
                "C1",
                Path(missing),
                None,
                "allowlist entry does not match a Markdown file",
                "remove the entry or restore the file",
            )
        )

    findings.extend(_duplicate_titles(scanned, root))
    return findings


def _relative(root: Path, path: Path) -> Path:
    return path.relative_to(root) if path.is_absolute() else path


def _title(path: Path) -> str | None:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return None


def _duplicate_titles(paths: Sequence[Path], root: Path) -> list[Finding]:
    seen: dict[str, Path] = {}
    findings: list[Finding] = []
    for path in paths:
        title = _title(root / path)
        if title is None:
            continue
        previous = seen.get(title)
        if previous is None:
            seen[title] = path
            continue
        findings.append(
            Finding(
                "C3",
                path,
                1,
                f"duplicate design title {title!r}, first used by {previous.as_posix()}",
                "keep one owner for the truth and point the other document at it",
            )
        )
    return findings


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    root = Path(arguments[0]) if arguments else Path.cwd()
    findings = check(root)
    for finding in findings:
        print(finding.render())
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
