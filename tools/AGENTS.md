# MavrykX — Verification tools

- `tools.verify` is the one gate. Do not call individual checks in scripts.
- Match evidence to the change: docs check for docs, focused tests for code, profile for user-visible work. Do not default to the full suite.
- Report each command and its result; never just "checks passed".
- `--fast` is the edit loop. `--full` adds tests, negatives, audits, lock and schema/RLS checks. Prerequisites are in [repo-scaffold](../docs/implementation/repo-scaffold.md).
- `tools/ownership.py` reads `ops.table_owner`. `tools/schema.py` reads the baseline digest, head and RLS.
