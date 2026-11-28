"""The RLS and audit probes against a disposable migrated database."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
RLS_TEST = ROOT / "docs" / "v1" / "schema" / "0002_rls_test.sql"
_UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")


def _dsn() -> str:
    url = os.environ.get("MAVRYKX_DATABASE_URL")
    if not url:
        pytest.skip("MAVRYKX_DATABASE_URL is not set")
    return url.replace("postgresql+asyncpg://", "postgresql://")


def _psql(dsn: str, *arguments: str) -> subprocess.CompletedProcess[str]:
    psql = shutil.which("psql")
    if psql is None:
        pytest.skip("psql is not installed")
    return subprocess.run(
        [psql, dsn, *arguments],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def _section(output: str, prefix: str) -> list[str]:
    sections: dict[str, list[str]] = {}
    current = ""
    for line in output.splitlines():
        if line.startswith(("probe ", "audit ")):
            current = line
            sections[current] = []
        elif current and line.strip() and not _UUID.match(line.strip()):
            sections[current].append(line.strip())
    return next((value for key, value in sections.items() if key.startswith(prefix)), [])


def test_rls_probes_on_a_disposable_database() -> None:
    dsn = _dsn()
    reset = _psql(
        dsn,
        "-q",
        "-c",
        "drop schema if exists app, audit, ref, ops cascade;",
        "-c",
        "drop table if exists alembic_version;",
    )
    assert reset.returncode == 0, reset.stderr

    upgrade = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=ROOT,
        env=os.environ.copy(),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    assert upgrade.returncode == 0, upgrade.stderr

    probes = _psql(dsn, "-qAt", "-f", str(RLS_TEST))
    assert probes.returncode == 0, probes.stderr

    assert _section(probes.stdout, "probe 1") == ["1"]
    assert _section(probes.stdout, "probe 2") == ["1"]
    assert _section(probes.stdout, "probe 4") == ["0"]
    assert _section(probes.stdout, "probe 5") == ["0"]
    assert _section(probes.stdout, "probe 6") == ["0"]
    assert _section(probes.stdout, "probe 14") == ["1"]
    assert _section(probes.stdout, "audit") == ["3|t", "t"]

    assert 'row-level security policy for table "document"' in probes.stderr
    assert 'row-level security policy for table "note"' in probes.stderr
    assert "application parent not found" in probes.stderr
    assert "application nesting deeper than 6" in probes.stderr
    assert "application matter and parent are immutable" in probes.stderr
    assert "only an admin may promote an admin" in probes.stderr
    assert probes.stderr.count("ERROR:") == 6
