"""The single baseline: execute docs/v1/schema/0001_core.sql."""

from __future__ import annotations

from alembic import op

from migrations.baseline import BASELINE, SHA256, digest
from migrations.sql_script import split_statements

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    source = BASELINE.read_bytes()
    if digest(source) != SHA256:
        raise RuntimeError(
            "baseline SQL changed; add a forward-only revision and update migrations/baseline.py"
        )
    for statement in split_statements(source.decode("utf-8")):
        op.execute(statement)


def downgrade() -> None:
    raise NotImplementedError("MavrykX migrations are forward-only")
