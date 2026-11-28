"""B8: every app table has exactly one manifest owner."""

from __future__ import annotations

import re
from pathlib import Path

from tools.findings import Finding

SCHEMA = Path("docs/v1/schema/0001_core.sql")
_TABLE = re.compile(r'(?m)^create table (?:if not exists )?app\.(?:"([^"]+)"|([a-z_]+))')
_OWNER_BLOCK = re.compile(r"insert into ops\.table_owner.*?on conflict \(table_name\)", re.S)
_OWNER_ROW = re.compile(r"\('([a-z_]+)','([a-z_]+)'\)")


def check(root: Path = Path()) -> list[Finding]:
    """Compare the app tables with the ops.table_owner manifest."""
    path = root / SCHEMA
    text = path.read_text(encoding="utf-8")
    tables = {quoted or plain for quoted, plain in _TABLE.findall(text)}
    owners: dict[str, str] = {}
    findings: list[Finding] = []

    for block in _OWNER_BLOCK.findall(text):
        for table, module in _OWNER_ROW.findall(block):
            if table in owners:
                findings.append(
                    Finding(
                        "B8",
                        path.relative_to(root),
                        None,
                        f"{table} has two owners",
                        "keep exactly one owner per table",
                    )
                )
            owners[table] = module

    for table in sorted(tables - set(owners)):
        findings.append(
            Finding(
                "B8",
                path.relative_to(root),
                None,
                f"{table} has no manifest owner",
                "add the table to ops.table_owner",
            )
        )

    for table in sorted(set(owners) - tables - {"audit_event"}):
        findings.append(
            Finding(
                "B8",
                path.relative_to(root),
                None,
                f"{table} is in the manifest but has no app table",
                "remove the manifest row or add the table",
            )
        )

    return findings


def main() -> int:
    findings = check()
    for finding in findings:
        print(finding.render())
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
