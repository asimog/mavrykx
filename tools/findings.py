"""The shared shape of a verification finding."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class Finding:
    """One failed rule, with the action that clears it."""

    rule: str
    path: Path
    line: int | None
    message: str
    fix: str

    def render(self) -> str:
        location = str(self.path) if self.line is None else f"{self.path}:{self.line}"
        return f"{self.rule}: {self.message} ({location})\n  fix: {self.fix}"


def render_all(findings: list[Finding]) -> str:
    return "\n".join(finding.render() for finding in findings)
