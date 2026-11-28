# MavrykX — Migrations

- The baseline is mutable when schema, code and tests change together.
- Update `migrations/baseline.py` and the RLS probes in the same change.
- Use a numbered forward-only revision when data must be preserved. `downgrade` is not implemented.
- Verify with `uv run alembic upgrade head` and the schema/RLS checks.
- Read the [domain model](../docs/v1/02-domain-model.md) and [SQL appendix](../docs/v1/schema/0001_core.sql) before changing a table.
