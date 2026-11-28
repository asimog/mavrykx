# MavrykX — Agent operating manual

**Status:** current · **Version:** 2 · **Date:** 2026-11-28

## A. Repository identity

MavrykX is a self-hosted legal-work platform for one firm. The Matter is the workspace; **Maverick** is
the one agent. The first product is the legal CRM and shared Matter workspace. Litigation management,
legal intelligence and Maverick follow on the same application services. A Matter may start with a note
alone; a client is optional at intake. The design is not a claim that the product exists.

This repository contains:

- `docs/v1/` — the five-document V1 design set and the SQL appendix. It is the design authority.
- `docs/implementation/` — working plans, pins, enforcement and the Euro-Office integration. They are
  not design authority.
- `docs/agents/` — issue-tracker and domain-doc consumer rules.
- `src/mavrykx/` — the verification spine: one `system.status` operation through an application
  service, FastAPI, Typer and a tool adapter; a minimal `ToolGateway`; the composition roots.
  `domain/`, `infrastructure/`, `agent/` and `composition/` are package stubs.
- `apps/desktop/` — Electron main and preload plus a React renderer shell.
- `migrations/` — Alembic revision `0001`, which executes the baseline SQL.
- `tools/` — `tools.verify` and the checks it runs.
- `tests/` — unit, integration and negative fixtures. `tests/e2e/` and `tests/contracts/` are empty.
- `vendor/euro-office/pg-adapter/` — the PostgreSQL queue adapter.
- `references/` — the Kosmos and Stella reference study. Nothing is vendored or built from it.

**Exists today:** the verification spine, the operation registry and its three surfaces, the Electron
shell, the baseline schema with Alembic and RLS probes, and the queue adapter. **Not implemented:**
`modules/`, CRM services, PostgreSQL repositories, the agent run loop, `AgentComposition`, the full
gateway pipeline, and the Euro-Office editor integration. Do not describe the design as implemented.

## B. Essential architecture rules

- **One writer per truth.** `docs/v1/02-domain-model.md` owns entities, ownership, lifecycles and
  invariants. `ops.table_owner` in the baseline schema names one module per table. No module writes
  another module's tables.
- **Application services own business operations.** Routes, CLI commands and tools are thin adapters;
  they call services, never repositories. Domain stays plain Python.
- **CLI, HTTP and agent tools use the same application capabilities.** The operation registry is the
  one definition of a business action; the three adapters must match it. The agent reaches services
  only through the one `ToolGateway`.
- **Permissions are enforced by the service and re-checked by RLS.** A firm admin is a lawyer and reads
  every Matter; every other user needs an active Matter grant. A restricted document needs a resource
  grant, except for the firm admin. An admin may delegate duties except promoting an admin; delegation
  never widens access. An agent inherits the initiating user and never gains wider access.
- **Every service write emits an audit event.** Every Matter-bound table carries `matter_id`, RLS, one
  owner and a negative test. Every mutation is revision- or base-bound; there is no last-write-wins.
- **Citations are legal records, not provider metadata.** A citation points to exactly one cited source:
  a judgment version, an instrument version or provision, a document version and anchor, or an external
  source. Pydantic AI `Citation` is transport; it never sets `verified`.
- **Documents have one edit lease.** Only the holder saves; a save is base-version and base-hash bound;
  a stale save is refused. Versions are immutable; restore creates a new version and resets approval.
  There is no real-time co-editing in V1.
- **DOCX/PDF is the work product; chat is not a legal record.** Conversations and runs are attributed
  records, not the document.
- **Approvals are human and hash-bound.** Commit, filing-ready, send, grant and delete are irreversible
  boundaries and are never model tools. `doc_apply` is tracked and reversible. An agent cannot approve
  its own work, clear a gate or delete a resource.
- **Unknown is a result.** An unverified rule or citation is `unconfirmed`, never `passed`. Only
  deterministic checks verify citations.
- **One agent.** Sub-agents are tools, not peers. One Pydantic AI Harness, one agent loop. A Harness
  Workspace is an execution environment, never the Matter.
- **No competing authority.** No second schema language, second application-service layer, second
  document authority, separate Workspace/Project entity, or conflict-check subsystem.
- **Do not change an approved decision without approval.** If a document and the code disagree, fix the
  owner document or the code in the same change. If the decision is unclear, stop and ask.

**Working vocabulary.** Use the definitions in `docs/v1/02-domain-model.md`. The highest-risk
distinctions: Matter ≠ proceeding; client ≠ contact; fact ≠ evidence; document ≠ version; task ≠
deadline; assignment is a task's assignee and due date; submission is task + version + approval; review
≠ approval; decision, approval and gate are different; a section is arrangement, not a workspace; an
application nests inside a Matter or proceeding and is never a sub-matter. Rejected entities:
`action`, `assignment` as a separate entity, sub-matter, per-Matter databases, Workspace/Project.

## C. Canonical documentation map

| Document | Owns | Read it when | Decisions made there |
|---|---|---|---|
| [`docs/v1/01-architecture.md`](docs/v1/01-architecture.md) | Product identity; system shape; modules and boundaries; stack choices; deployment; product build order; acceptance gates. | Changing module boundaries, stack, deployment or build order; checking what is implemented versus designed. | Module ownership, deployment shape, build order, acceptance. Exact pins are in the scaffold. |
| [`docs/v1/02-domain-model.md`](docs/v1/02-domain-model.md) | Definitions; entities; table ownership; relationships; lifecycles; invariants; the SQL appendix relationship. | Naming or modelling any domain concept; before a schema change; when ownership is unclear. | Entities, ownership, lifecycles, invariants, what is not an entity. |
| [`docs/v1/03-application-agent-and-data.md`](docs/v1/03-application-agent-and-data.md) | Application services; service contracts; the gateway; Pydantic AI and the Harness; workflows; CLI; data; documents; security; audit. | Adding a service, tool, workflow, CLI command or data path; before an agent capability. | Service boundaries, gateway rules, agent composition, data and audit rules. |
| [`docs/v1/04-shared-workspaces-and-collaboration.md`](docs/v1/04-shared-workspaces-and-collaboration.md) | Matter workspace; firm roles and Matter access; the resource model; sequential editing; the edit lease and save contract; submission and review; distributed execution. | Changing access, document editing, collaboration or execution. | Access policy, edit lease, conflict handling, review flow. |
| [`docs/v1/05-product-experience.md`](docs/v1/05-product-experience.md) | Navigation; Today; the Matter workspace; document view; the Maverick dock; review inbox; settings; onboarding. | Adding or changing a user-facing surface. | Product surfaces and interaction rules. |
| [`docs/v1/schema/0001_core.sql`](docs/v1/schema/0001_core.sql) and [`0002_rls_test.sql`](docs/v1/schema/0002_rls_test.sql) | Baseline DDL and RLS probes. The domain model is the source; SQL must match it. | Before any schema or migration work. | Table shapes, RLS policies, the executable `ops.table_owner` copy of the domain owner map. The baseline is mutable: edit it only with the schema, code and tests together, update `migrations/baseline.py` and the RLS fixtures, and run `--full`. Use a revision only when data must be preserved. |
| [`docs/implementation/repo-scaffold.md`](docs/implementation/repo-scaffold.md) | Repository layout; exact pins; lockfile rules; verification commands. | Adding a dependency, changing a pin, or running a check. | Pins, layout, command surface. |
| [`docs/implementation/enforcement-audit-plan.md`](docs/implementation/enforcement-audit-plan.md) | Rule catalogue; checks; negative tests; enforcement status. | Adding a rule or claiming a boundary is enforced. | Rule IDs, proofs, current coverage. |
| [`docs/implementation/eurooffice-integration-plan.md`](docs/implementation/eurooffice-integration-plan.md) | Euro-Office local editor integration; sequential editing; deferred shared-session topology; packaging decisions. | Editor, `x2t`, lease or shared-session work. | Editor integration and deferred topology. |
| [`docs/implementation/euro-office-runtime.md`](docs/implementation/euro-office-runtime.md) | Euro-Office package reduction, measurements and licence findings. | Changing the editor package or distribution. | Package allowlist, removals, licence obligations. |
| [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md) | GitHub Issue conventions; no triage vocabulary; wayfinder operations. | Creating, reading or closing issues, specs or tickets. | Tracker operations and labels. |
| [`docs/agents/domain.md`](docs/agents/domain.md) | How skills consume the domain docs; no `GLOSSARY.md` or ADR tree. | Using `domain-modeling` or writing domain vocabulary. | Where domain-modelling output goes. |
| [`vendor/euro-office/pg-adapter/README.md`](vendor/euro-office/pg-adapter/README.md) | Queue adapter configuration, schema and smoke test. | Changing the queue adapter or its schema. | Adapter facts. |
| [`references/README.md`](references/README.md) | Reference-repository study and reuse restrictions. | Considering a pattern from Kosmos or Stella. | Reference facts, not design authority. |
| [`README.md`](README.md) | Repository entry point and index. | First visit. | Navigation only; no design decisions. |
| [`skills-lock.json`](skills-lock.json), `.agents/skills/` and `.opencode/commands/` | Installed skill inventory, skill text and slash-command wrappers. | Before invoking a skill. | Skill mechanics, not architecture. |

**One owner per truth.** If two documents disagree, the owner above wins; fix the other. Do not create
a new document to avoid deciding ownership. A design amendment lands in the owner; a working-rule
amendment lands here. `docs/v1/` is design authority; `docs/implementation/` is plans. No `FINAL`,
`UPDATED`, `NEW` or `V2` names. New Markdown needs an allowlist reason. When adding or renaming a
document, update the root `README.md` and the architecture doc. Match the house style of the document you
edit: `# MavrykX — <name>`, a status/version/date line, terse declarative prose, British spelling, lists
for decisions and mermaid for diagrams.

## D. Technology and implementation constraints

- Python **3.14** (`>=3.14,<3.15`); Node **26.13.1** build and tooling; Electron **45.5.0** with Node
  **24.22.3**. Electron's Node is the native-module ABI; the build Node is not.
- PostgreSQL **17.12** is the product baseline; pgvector **0.8.7**. Pydantic **2.14.4**. Pydantic AI
  Harness **0.75.0**, pinned exactly; it requires `pydantic-ai-slim` **2.75.0**.
- Do not declare `pydantic-ai`, `pydantic-ai-slim` or `pydantic-graph` separately. Add provider extras
  to `pydantic-ai-slim`. Verify capability names against the pinned Harness before composing.
- TypeScript **6.0.3**, not 7.0.2: `typescript-eslint` 8.74 supports `<6.1.0`.
- One OpenAPI source: FastAPI emits it; `openapi-typescript` generates the client. No hand-written
  request types. Pydantic at the boundaries; SQLAlchemy for persistence; no SQLModel; no Zod.
- PostgreSQL is authoritative; blobs are content-addressed; the queue is PostgreSQL. No RabbitMQ,
  Erlang, Redis, Nextcloud or CommunityServer in the record path. No hosted DocumentServer and no
  Docker product dependency.
- Euro-Office **9.3.8** only. V1 runs the embedded local editor and `x2t`; the target installer carries
  the server pack but V1 does not start it. Do not mix `web-apps`, `sdkjs` or `x2t` from different
  releases.
- Migrations: revision `0001` executes `docs/v1/schema/0001_core.sql`. The baseline is mutable when the
  schema, code and tests change together; update `migrations/baseline.py` and the RLS fixtures and run
  `--full`. Use a numbered forward-only revision when data must be preserved; `downgrade` is not
  implemented. `alembic check` is the intended model-drift gate once SQLAlchemy models exist; today
  `tools/schema.py` checks the baseline digest, migration head and RLS.
- Exact pins and the pairs that move together are in
  [`docs/implementation/repo-scaffold.md`](docs/implementation/repo-scaffold.md) §1. The lockfiles are
  the evidence; a prose pin that disagrees with a lockfile is a defect.

## E. Verification rules

Commands:

```bash
uv run python -m tools.verify --fast
uv run python -m tools.verify --full
uv run python -m tools.verify --rule E8
```

`docs/implementation/repo-scaffold.md` §4 owns the command surface; this section is the operating summary.

`--fast` runs the Markdown policy, comment policy, mypy, TypeScript, ruff, ESLint, import-linter,
dependency-cruiser, operation-parity and table-ownership checks. `--full` adds pytest, the negative
fixtures, `pip-audit` and `npm audit`, `uv lock --check`, and the baseline/RLS schema check. It requires a
disposable PostgreSQL 17.12 + pgvector database, `MAVRYKX_DATABASE_URL`, `psql` on `PATH`, and
`uv run alembic upgrade head`. Without `psql`, the RLS probe test skips. The integration test drops and
recreates the `app`, `audit`, `ref` and `ops` schemas.

CI is not used for this local setup. Run `--full` locally. If CI is re-enabled, it runs `--full` on
`pgvector/pgvector:pg17` (PostgreSQL 17.12) and the `verify` check is required on `main`. E2E,
contract-drift, court-leak and docs-agree checks are **not wired yet**; do not claim they ran.

Required coverage for a change:

- **Schema or migration:** a baseline edit with `migrations/baseline.py` and the RLS fixtures updated, or
  a forward-only revision when data must be preserved; `alembic upgrade head`; `--full`.
- **Permissions:** negative fixtures for a non-member, the firm admin, a restricted document, a
  cross-Matter read or write, and a revoked grant. The service check and the RLS check share the same
  fixture.
- **Services:** an audit event in the same transaction; idempotent replay; a stale revision or document
  base refused; CLI, HTTP and tool parity.
- **Module boundaries:** import-linter, dependency-cruiser and operation parity. Add the module-layer
  contracts with the first product module.
- **Agent tools:** a catalog entry, a bundle and an eval; human-only operations are never registered as
  tools; every call goes through the gateway.
- **Business rules:** use `tdd` for permissions, data integrity and other testable behaviour.

Report the exact command and the actual result. A check that could not run is a failure to report, not
a pass. Do not weaken a gate for speed.

## F. Skills and engineering workflow

The skills are vendored at `.agents/skills/` and pinned in `skills-lock.json`. They are working methods,
not architectural authorities. `docs/v1/`, this file and the owning document win over a skill's generic
defaults. If a skill conflicts with the repository, flag it; do not silently follow the skill.

The implementation strategy is **complete-module development**: map the whole application at a high
level first; design the next module in detail; approve its design and specification; implement the
complete module; verify it; then move to the next module. Do not use skeleton-first or
vertical-slice-first implementation as the default. A module is not done until its services, schema,
permissions, audit, tests and surfaces are complete and its gate passes.

| Step | Invocation | Use |
|---|---|---|
| 1 | `/wayfinder` | Establish the overall module map, dependencies and implementation order. It writes a map issue and decision tickets; it plans, it does not implement. |
| 2 | `/grill-with-docs` | Investigate and challenge the next module's design. The command calls `grilling` and `domain-modeling`. |
| 3 | `domain-modeling` | Load the skill with id `domain-modeling` when entities, ownership or relationships need detailed modelling. In this repo output goes to `docs/v1/02-domain-model.md`; do not create `GLOSSARY.md` or `docs/adr/`. |
| 4 | `/to-spec` | Turn the approved module design into an implementation spec in GitHub Issues. This repo has no triage vocabulary: publish with no state label. The skill's generic `ready-for-agent` instruction does not apply. |
| 5 | `/to-tickets` | Use only when the module needs task-level planning. The skill defaults to tracer-bullet slices; this repo's complete-module strategy wins. Tickets are workstreams within the approved module, not an alternative architecture. |
| 6 | `/implement-spec` | Implement the approved spec on one integration branch, using `tdd` at the seams and `code-review` at the end. |
| 7 | `tdd` | Load the skill with id `tdd` for business rules, permissions, data integrity and other testable behaviour. |
| 8 | `code-review` | Load the skill with id `code-review` after implementation; it reviews standards and spec independently. |
| 9 | `/retro` | Use when a module or substantial phase is complete; improve the agent environment, not the architecture. |

`/wayfinder`, `/grill-with-docs`, `/to-spec`, `/to-tickets`, `/implement-spec` and `/retro` are installed
OpenCode commands in `.opencode/commands/`; each loads the skill of the same id. `domain-modeling`,
`tdd` and `code-review` are installed skills without a slash command: load them with the skill tool.
`grill-me` is an installed command that calls `grilling`; use it only when docs output is not wanted.

Supporting skills: `codebase-design` (deep modules), `grilling` (the interview engine behind
`grill-with-docs`), `diagnosing-bugs`, `research`, `prototype`, `pr`, `handoff`, `writing-for-agents`,
`improve-codebase-architecture`, `ask-matt`, `to-questionnaire`, `teach`, `wait-what`, `wizard`,
`implement` (older direct implementation; prefer `/implement-spec` for specs), `triage` (installed but
not used here: solo repo, no triage vocabulary) and `setup-matt-pocock-skills` (already configured; do
not rerun). The Matt Pocock flow and GitHub Issues are the only spec and ticket process; there is no
second pipeline.
