# AGENTS.md

**This repository holds the V1 design and the first implementation work for MavrykX** — a self-hosted
legal-work platform whose one agent is **Maverick**. The design set is `docs/v1/`; implementation
plans are `docs/implementation/`; the first code is the Euro-Office PostgreSQL adapter under
`vendor/euro-office/`. There is no application build, CI or test suite yet beyond that adapter's
smoke test.

The design is not a claim that the product exists.

## Read in this order

- [`docs/v1/01-architecture.md`](docs/v1/01-architecture.md) — system shape, modules, stack, dependency enforcement, deployment, build order, acceptance.
- [`docs/v1/02-domain-model.md`](docs/v1/02-domain-model.md) — definitions, entities, relationships, lifecycles, invariants, matter-intelligence plan.
- [`docs/v1/03-application-agent-and-data.md`](docs/v1/03-application-agent-and-data.md) — application services, gateway, Pydantic AI/Harness, workflows, CLI, data, documents, security, audit.
- [`docs/v1/04-shared-workspaces-and-collaboration.md`](docs/v1/04-shared-workspaces-and-collaboration.md) — Matter workspace, conversations, access, live editing, distributed execution, submissions.
- [`docs/v1/05-product-experience.md`](docs/v1/05-product-experience.md) — navigation, Today, Matter workspace, classification setup, documents, browser, Research Studio, library, workflows, inbox, onboarding.
- [`docs/v1/schema/0001_core.sql`](docs/v1/schema/0001_core.sql) and [`0002_rls_test.sql`](docs/v1/schema/0002_rls_test.sql) — the SQL appendix.
- [`docs/implementation/repo-scaffold.md`](docs/implementation/repo-scaffold.md) — repository shape, pins, verification command.
- [`docs/implementation/enforcement-audit-plan.md`](docs/implementation/enforcement-audit-plan.md) — rules, checks and negative tests.
- [`docs/implementation/eurooffice-integration-plan.md`](docs/implementation/eurooffice-integration-plan.md) — editor modes and service topology.
- [`docs/implementation/euro-office-runtime.md`](docs/implementation/euro-office-runtime.md) — package reduction and licence findings.
- [`vendor/euro-office/pg-adapter/README.md`](vendor/euro-office/pg-adapter/README.md) — the PostgreSQL queue adapter.

There is no separate decision register, sources file, concerns file or prompt folder. Decisions live
in the document where they apply. Sources are cited inline where relevant.

## Fixed choices

- Electron desktop; React renderer; Python server.
- Pydantic for contracts; Pydantic AI for the agent; the Pydantic AI Harness for agent machinery.
- PostgreSQL authoritative; content-addressed blobs for bytes; the queue is PostgreSQL.
- One agent, Maverick. Sub-agents are tools, not peers.
- Self-hosted per firm; one installation serves one firm.
- Human approval for commit, filing, send, grant, delete.
- DOCX/PDF is the work product; chat is not a legal record.
- Matters may start with a note alone; a client is optional at intake.
- Indian forums only.
- One application-service layer; CLI, HTTP and agent tools call it.
- No conflict-check subsystem; the matter-open gate records client and scope.
- Euro-Office 9.3.8 is the editor. Every client installs the server pack; only a shared session runs it.
- No RabbitMQ, Erlang, Redis, Nextcloud or CommunityServer as part of the record path.

## Laws for design content

- One writer per truth: every table has one owning module. The agent never writes legal records directly; it goes through application services via the tool gateway.
- Every legal table carries `matter_id`, has an RLS policy, a named owner and a negative test.
- Every tool has a catalog entry, a bundle and an eval.
- Every service write calls the audit append.
- Unknown is a result: an unverified rule or citation is `unconfirmed`, never `passed`. Only deterministic checks verify citations; a model may only propose one.
- No conflict-check subsystem.
- Stateless execution, one authoritative record: runs execute on the advocate's node; every tool call crosses the live session to the server's one gateway; access is standing until revoked; commits, approvals and decisions are server transactions; the file cache is derived.
- Positions, evidence assessments, exhibit numbers and registry identity are append-only attributed records; status columns are derived.
- Approval friction sits only on irreversible boundaries: commit, filing-ready, send, grant, delete. `doc_apply` is tracked and reversible and gets batch review. A gate is never weakened for speed.
- Every agent-drafted document and filing set references the task or decision that authorised it.
- No data migration from a prior product: one baseline schema, forward-only numbered migrations before pilot data.
- Prose does not enforce: boundaries, isolation, catalog parity and bundle evals are CI checks.
- Installed is not running: the server pack is present on every client; starting it is a shared-session act.
- The editor is not the record. Euro-Office renders; `x2t` converts; the builder is the only writer; `lxml` reads for verification.
- A run workspace is not the Matter and not the record. Scratch files are scoped, owned, limited and deletable; legal versions are none of those.
- One runtime pin: the harness pins the agent runtime. No second harness, no second agent loop, no second schema language.

## Domain vocabulary

Matter ≠ proceeding · hearing ≠ order · fact ≠ evidence · document ≠ version · authority ≠ citation · task ≠ deadline · decision, approval and gate are different · an application nests inside a matter or proceeding and is never a sub-matter · the server is the shared-record spine; execution is stateless and local.

Rejected entities: `action`, `assignment`, sub-matter, per-matter databases, a conflict-check subsystem, Workspace/Project.

Out of scope: time/billing, teams, client portal, multi-tenant SaaS.

## Matter management versus legal intelligence

- **Matter management** is the Clio-shaped substrate: firm, people, clients, Matters, parties, tasks, dates, notes, documents and access. It works with notes alone.
- **Litigation management** is Proceedings, applications, hearings, orders, forum adapters and filings.
- **Legal intelligence** is classification, corpus, case law, library, research, evidence, drafting and verification.
- **Agent and automation** is runs, tools, browser and workflows.

Do not force legal intelligence into matter creation.

## SQL appendix

- `0001_core.sql` is the appendix to the domain model. The domain model is the source; if they conflict, fix the SQL.
- It targets PostgreSQL 17+ (`pgcrypto`, `citext`, `pg_trgm`, `pgvector`) and runs as the `maverick_owner` role.
- Conventions: UUID keys, timestamptz, text + CHECK for stable sets, immutable tables reject UPDATE/DELETE, derived data separate and rebuildable.
- `0002_rls_test.sql` seeds two Matters and proves isolation, walls, the application tree and the audit link.
- If you change a schema file, re-run the pair and update the results in the architecture doc.
- Alembic is the runner: revision `0001` executes the baseline SQL; later revisions are numbered and forward-only; `downgrade` is not implemented; `alembic check` fails on drift.

## Three Pydantic libraries, three jobs

- **Pydantic Validation** — application contracts: API models, DTOs, tool inputs/outputs, settings, strict mode. Domain entities stay plain Python; Pydantic lives at the boundaries.
- **Pydantic AI** — the agent framework: the run loop, typed tools, structured output and model access. Core capabilities — workspaces such as `LocalWorkspace`, `WebSearch`, MCP, thinking, tool search and provider-native compaction — live in `pydantic_ai.capabilities`.
- **Pydantic AI Harness** — an optional capability library, not a runtime: coding, code mode, sub-agents, memory, skills, compaction, guardrails and sandboxes. MavrykX's `AgentComposition` chooses which capabilities a bundle gets and builds the one `Agent`; it is not a second harness.

Pin `pydantic-ai-harness==0.75.0` exactly. It requires `pydantic-ai-slim==2.75.0`; do not pin
`pydantic-ai` or `pydantic-graph` separately. Add provider extras to `pydantic-ai-slim`. Capability
names drift between minors; verify each name against the pinned version before composing.

Pydantic AI names: **tool** is one callable; **Harness capability** is a Pydantic AI composable unit; **bundle** is the MavrykX selection; **Workspace** is an execution environment, never the Matter; **workflow** is Pydantic Graph; `Dynamic Workflow` is named in full.

## Stack rules

The full pinned table is in [`docs/implementation/repo-scaffold.md`](docs/implementation/repo-scaffold.md) §1. The rules that prevent the expensive mistakes:

- TypeScript **6.0.3**, not 7.0.2: `typescript-eslint` 8.74 supports `<6.1.0`.
- Electron **45.5.0** carries Chromium **156.0.8078.109** and Node **24.22.3**. That Node is the native-module ABI; the build Node 26.13.1 is not.
- PostgreSQL **17.12** is the product baseline. A development machine's 18.1 is not the product.
- The queue is the PostgreSQL adapter in `vendor/euro-office/pg-adapter/`. No RabbitMQ, no Erlang, no Redis.
- Pydantic at the boundaries; SQLAlchemy for persistence; no SQLModel in the domain; no Zod in the renderer.
- One OpenAPI source: FastAPI emits it, `openapi-typescript` generates the client. No hand-written request types.

## Editor modes

- **Local.** The client embeds the Euro-Office frontend and `x2t`. No `DocService` process. Saves go through the MavrykX API.
- **Shared.** A client or the firm server starts `DocService`, `FileConverter` and the PostgreSQL queue; peers connect over the LAN. The host is the session authority while the session lasts.
- The same 9.3.8 build serves both; do not mix `web-apps`, `sdkjs` or `x2t` from different releases.

## Tooling

- There is no second spec pipeline. Matt Pocock's flow and GitHub Issues are the only process for specs, tickets and implementation.
- Matt Pocock's skills are vendored at `.agents/skills/`, pinned in `skills-lock.json`. They are working discipline, not design authority.
- The enforcement plan defines one command, `python -m tools.verify`, with fast and full modes. Hooks are convenience; CI is the gate. Until it exists, the adapter's `node test/smoke.js` is the only executable check.
- Application code starts only after the enforcement plan is approved and the scaffold exists. The first code is the adapter; do not expand it into application modules.

## Agent skills

### Issue tracker

Issues, specs and decision tickets live in GitHub Issues on `asimog/mavrykx`. Solo repo, no triage vocabulary. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context, but vocabulary lives in `AGENTS.md` § Domain vocabulary and `docs/v1/02-domain-model.md`; there is no `GLOSSARY.md` or `docs/adr/`. See `docs/agents/domain.md`.

## Governance

This file is the operating brief and `docs/v1/` is the design authority. There is no separate
governance document or second process. A design amendment lands in the document that owns the
decision; a working-rule amendment lands here. The enforcement plan defines the checks.

## House document style

- Title `# MavrykX — <name>` (the architecture doc is `# MavrykX — Detailed architecture`), then a `**Status:**` / `**Version:**` / `**Date:**` line.
- Terse declarative prose; lists for decisions and rules; tables only where comparison helps; mermaid for diagrams; British spelling.
- Docs state the design as it stands. They do not narrate amendments, reviews or prior implementations.
- Cross-link inside `docs/v1/`. New sources are cited inline where relevant.
- When adding or renaming a document, update the root `README.md` and the architecture doc.
