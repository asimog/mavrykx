"""E8: the baseline digest, the migration head and the RLS invariants."""

from __future__ import annotations

import asyncio
import hashlib
import os
from dataclasses import dataclass
from pathlib import Path

import asyncpg
from alembic.config import Config
from alembic.script import ScriptDirectory

from migrations.baseline import BASELINE, SHA256
from tools.findings import Finding

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True, slots=True)
class _Database:
    versions: tuple[str, ...]
    app_tables: int
    without_rls: int
    without_policy: int


def check() -> list[Finding]:
    findings: list[Finding] = []

    if hashlib.sha256(BASELINE.read_bytes()).hexdigest() != SHA256:
        findings.append(
            Finding(
                "E8",
                BASELINE.relative_to(ROOT),
                None,
                "baseline SQL differs from the bytes revision 0001 executes",
                "add a forward-only revision and record the new digest in migrations/baseline.py",
            )
        )

    heads = _heads()
    if len(heads) != 1:
        findings.append(
            Finding(
                "E8",
                Path("migrations/versions"),
                None,
                f"expected one migration head, found {len(heads)}",
                "linearise the revision graph",
            )
        )

    url = os.environ.get("MAVRYKX_DATABASE_URL")
    if not url:
        findings.append(
            Finding(
                "E8",
                Path("alembic.ini"),
                None,
                "MAVRYKX_DATABASE_URL is not set",
                "start PostgreSQL 17.12 with pgvector, set the URL and run alembic upgrade head",
            )
        )
        return findings

    try:
        database = asyncio.run(_inspect(url))
    except (OSError, asyncpg.PostgresError) as error:
        findings.append(
            Finding(
                "E8",
                Path("migrations"),
                None,
                f"database is not migrated: {error}",
                "run alembic upgrade head against the configured database",
            )
        )
        return findings

    if set(database.versions) != set(_heads()):
        findings.append(
            Finding(
                "E8",
                Path("migrations"),
                None,
                f"database is at {database.versions or 'no revision'}, expected {_heads()}",
                "run alembic upgrade head",
            )
        )
    if database.app_tables == 0:
        findings.append(
            Finding(
                "E8",
                Path("migrations"),
                None,
                "the database has no app tables",
                "run alembic upgrade head",
            )
        )
    if database.without_rls:
        findings.append(
            Finding(
                "E8",
                Path("docs/v1/schema/0001_core.sql"),
                None,
                f"{database.without_rls} app tables have no row-level security",
                "enable RLS on the table and add its policy",
            )
        )
    if database.without_policy:
        findings.append(
            Finding(
                "E8",
                Path("docs/v1/schema/0001_core.sql"),
                None,
                f"{database.without_policy} app tables with matter_id have no policy",
                "add a matter-scoped policy",
            )
        )
    return findings


def _heads() -> list[str]:
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "migrations"))
    return ScriptDirectory.from_config(config).get_heads()


async def _inspect(url: str) -> _Database:
    connection = await asyncpg.connect(url.replace("postgresql+asyncpg://", "postgresql://"))
    try:
        versions = tuple(
            str(row["version_num"])
            for row in await connection.fetch("select version_num from alembic_version")
        )
        app_tables = int(
            await connection.fetchval("select count(*) from pg_tables where schemaname = 'app'")
        )
        without_rls = int(
            await connection.fetchval(
                """
                select count(*) from pg_tables t
                where t.schemaname = 'app'
                  and not exists (
                    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'app' and c.relname = t.tablename and c.relrowsecurity
                  )
                """
            )
        )
        without_policy = int(
            await connection.fetchval(
                """
                select count(*) from pg_tables t
                where t.schemaname = 'app'
                  and exists (
                    select 1 from information_schema.columns c
                    where c.table_schema = 'app'
                      and c.table_name = t.tablename
                      and c.column_name = 'matter_id'
                  )
                  and not exists (
                    select 1 from pg_policies p
                    where p.schemaname = 'app' and p.tablename = t.tablename
                  )
                """
            )
        )
    finally:
        await connection.close()
    return _Database(versions, app_tables, without_rls, without_policy)
