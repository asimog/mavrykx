# MavrykX

**Architecture and the verification spine.** MavrykX is the platform; **Maverick** is the one agent.
The design set is `docs/v1/`. The verification spine, a minimal `system.status` operation across HTTP,
CLI and tool, the Electron shell, the Alembic baseline with RLS probes, and the Euro-Office PostgreSQL
adapter are implemented. No product module exists yet.

For agents, read [AGENTS.md](AGENTS.md). Start here: [docs/v1/01-architecture.md](docs/v1/01-architecture.md).

| Doc | Contents |
|---|---|
| [Detailed architecture](docs/v1/01-architecture.md) | System shape, modules, stack, dependency enforcement, deployment, build order, acceptance |
| [Domain model](docs/v1/02-domain-model.md) | Definitions, entities, relationships, lifecycles, invariants, matter-intelligence plan |
| [Application, agent and data](docs/v1/03-application-agent-and-data.md) | Application services, gateway, Pydantic AI/Harness, workflows, CLI, data, documents, security, audit |
| [Shared workspaces and collaboration](docs/v1/04-shared-workspaces-and-collaboration.md) | Matter workspace, roles, sequential editing, access, review, distributed execution |
| [Product experience](docs/v1/05-product-experience.md) | Navigation, Today, Matter workspace, classification setup, documents, browser, Research Studio, library, workflows, inbox, onboarding |

The SQL appendix remains at [docs/v1/schema/0001_core.sql](docs/v1/schema/0001_core.sql); it is not a
sixth document. The RLS probes are [0002_rls_test.sql](docs/v1/schema/0002_rls_test.sql).

Working plans (status per document):

- [Repository scaffold](docs/implementation/repo-scaffold.md)
- [Enforcement audit](docs/implementation/enforcement-audit-plan.md)
- [Euro-Office integration](docs/implementation/eurooffice-integration-plan.md)
- [Euro-Office runtime analysis](docs/implementation/euro-office-runtime.md)

Agent consumer rules: [issue tracker](docs/agents/issue-tracker.md) and [domain docs](docs/agents/domain.md).
Reference repositories: [reference study](references/README.md) — Kosmos and Stella, pinned commits,
test results, patterns and reuse restrictions. The clones live outside this repository; no upstream
code is vendored or built.

## Working in the repository

```bash
uv sync
npm ci
uv run python -m tools.verify --fast
uv run python -m tools.verify --full
```

The command surface and full check list are in
[repo-scaffold.md](docs/implementation/repo-scaffold.md) §4. `--fast` is the edit loop: Markdown and
comment policy, mypy, TypeScript, ruff, ESLint, import-linter, dependency-cruiser and operation parity.
`--full` adds pytest, the negative fixtures, `pip-audit` and `npm audit`, `uv lock --check`, and the
baseline/RLS schema check. It requires Python 3.14, `uv` 0.13.10, Node 26.13.1, `psql` on `PATH`, and a
disposable PostgreSQL 17.12 database with pgvector:

```bash
docker run --rm -d --name mavrykx-pg -p 55433:5432 \
  -e POSTGRES_USER=maverick_owner -e POSTGRES_PASSWORD=maverick -e POSTGRES_DB=mavrykx \
  pgvector/pgvector:pg17
export MAVRYKX_DATABASE_URL=postgresql+asyncpg://maverick_owner:maverick@127.0.0.1:55433/mavrykx
uv run alembic upgrade head
uv run python -m tools.verify --full
```

Docker is a development convenience here, never a product dependency. The integration test drops and
recreates the `app`, `audit`, `ref` and `ops` schemas; point it only at a disposable database.

CI runs `--full` on every pull request and on pushes to `main` against `pgvector/pgvector:pg17`
(PostgreSQL 17.12); the `verify` check is required on `main`. E2E, contract-drift, table-ownership,
court-leak and docs-agree checks are not wired yet.

**Build in the architecture doc's order.** Each step's gate must pass before the next. The design is
not a claim that the product exists.
