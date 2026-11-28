# MavrykX

**Architecture and the verification spine.** MavrykX is the platform; **Maverick** is the one agent.
The design set is `docs/v1/`; the scaffold, operation registry and checks exist; no product module
does yet. The scaffold and the Euro-Office PostgreSQL adapter under
[`vendor/euro-office/pg-adapter/`](vendor/euro-office/pg-adapter/README.md) are the working code.

Start here: [docs/v1/01-architecture.md](docs/v1/01-architecture.md).

| Doc | Contents |
|---|---|
| [Detailed architecture](docs/v1/01-architecture.md) | System shape, modules, stack, dependency enforcement, deployment, build order, acceptance |
| [Domain model](docs/v1/02-domain-model.md) | Definitions, entities, relationships, lifecycles, invariants, matter-intelligence plan |
| [Application, agent and data](docs/v1/03-application-agent-and-data.md) | Application services, gateway, Pydantic AI/Harness, workflows, CLI, data, documents, security, audit |
| [Shared workspaces and collaboration](docs/v1/04-shared-workspaces-and-collaboration.md) | Matter workspace, roles, sequential editing, access, review, distributed execution |
| [Product experience](docs/v1/05-product-experience.md) | Navigation, Today, Matter workspace, classification setup, documents, browser, Research Studio, library, workflows, inbox, onboarding |

The SQL appendix remains at [docs/v1/schema/0001_core.sql](docs/v1/schema/0001_core.sql); it is not a sixth document.

Implementation plans:

- [Repository scaffold](docs/implementation/repo-scaffold.md)
- [Enforcement audit](docs/implementation/enforcement-audit-plan.md)
- [Euro-Office integration](docs/implementation/eurooffice-integration-plan.md)
- [Euro-Office runtime analysis](docs/implementation/euro-office-runtime.md)

Reference repositories:

- [Reference study](references/README.md) — Kosmos and Stella, pinned commits, test results, patterns and reuse restrictions. The clones live outside this repository; no upstream code is vendored or built.

## Working in the repository

```bash
uv sync
npm ci
uv run python -m tools.verify --fast
uv run python -m tools.verify --full
```

`--fast` is the edit loop. `--full` adds tests, the negative suite, dependency audits, lockfile drift,
the schema checks and the RLS probes, and is what CI runs. Python 3.14 and `uv` 0.13.10 are required;
Node is pinned to 26.13.1 in `.node-version`.

`--full` needs a disposable PostgreSQL 17.12 database with pgvector:

```bash
docker run --rm -d --name mavrykx-pg -p 55433:5432 \
  -e POSTGRES_USER=maverick_owner -e POSTGRES_PASSWORD=maverick -e POSTGRES_DB=mavrykx \
  pgvector/pgvector:pg17
export MAVRYKX_DATABASE_URL=postgresql+asyncpg://maverick_owner:maverick@127.0.0.1:55433/mavrykx
uv run alembic upgrade head
```

The integration test drops and recreates the `app`, `audit`, `ref` and `ops` schemas; point it only at
a disposable database.

**The whole system is the scope.** Do not build until the gate conditions in the architecture doc pass.
