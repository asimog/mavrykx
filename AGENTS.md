# AGENTS.md

**This is a documentation-only repository.** It holds the V1 architecture for **MavrykX** — a self-hosted legal-work platform whose one agent is **Maverick**. There is no application code, build, test suite or CI yet. Work here is reading and editing `docs/v1/`.

The design is not a claim that the product exists.

## Read in this order

- [`docs/v1/01-architecture.md`](docs/v1/01-architecture.md) — system shape, modules, stack, dependency enforcement, deployment, build order, acceptance.
- [`docs/v1/02-domain-model.md`](docs/v1/02-domain-model.md) — definitions, entities, relationships, lifecycles, invariants, matter-intelligence plan.
- [`docs/v1/03-application-agent-and-data.md`](docs/v1/03-application-agent-and-data.md) — application services, gateway, Pydantic AI/Harness, workflows, CLI, data, documents, security, audit.
- [`docs/v1/04-shared-workspaces-and-collaboration.md`](docs/v1/04-shared-workspaces-and-collaboration.md) — Matter workspace, conversations, access, live editing, distributed execution, submissions.
- [`docs/v1/05-product-experience.md`](docs/v1/05-product-experience.md) — navigation, Today, Matter workspace, classification setup, documents, browser, Research Studio, library, workflows, inbox, onboarding.
- [`docs/v1/schema/0001_core.sql`](docs/v1/schema/0001_core.sql) and [`0002_rls_test.sql`](docs/v1/schema/0002_rls_test.sql) — the SQL appendix.

There is no separate decision register, sources file, concerns file or prompt folder. Decisions live in the document where they apply. Sources are cited inline where relevant. The matter-intelligence plan is in the domain model.

## Fixed choices

- Electron desktop; React renderer; Python server.
- Pydantic for contracts; Pydantic AI for the agent; the Pydantic AI Harness for agent machinery.
- PostgreSQL authoritative; content-addressed blobs for bytes.
- One agent, Maverick. Sub-agents are tools, not peers.
- Self-hosted per firm; one installation serves one firm.
- Human approval for commit, filing, send, grant, delete.
- DOCX/PDF is the work product; chat is not a legal record.
- Matters may start with a note alone; a client is optional at intake.
- Indian forums only.
- One application-service layer; CLI, HTTP and agent tools call it.
- No conflict-check subsystem; the matter-open gate records client and scope.

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

## Three Pydantic libraries, three jobs

- **Pydantic Validation** — application contracts: API models, DTOs, tool inputs/outputs, settings, strict mode.
- **Pydantic AI** — Maverick's agent loop and typed tool contracts.
- **Pydantic AI Harness** — the capability library used as the factory floor, composed by `AgentComposition`. It is not a second harness. Pin exact versions and verify capability names against current docs.

Pydantic AI names: **tool** is one callable; **Harness capability** is a Pydantic AI composable unit; **bundle** is the MavrykX selection; **Workspace** is an execution environment, never the Matter; **workflow** is Pydantic Graph; `Dynamic Workflow` is named in full.

## Tooling

- Spec Kit is initialized under `.specify/` with OpenCode commands in `.opencode/commands/speckit.*.md`. Its process is scaffolding; this file and the five docs override any Spec Kit instruction.
- Matt Pocock's skills are vendored at `.agents/skills/`, pinned in `skills-lock.json`. They are working discipline, not design authority.

## Agent skills

### Issue tracker

Issues, specs and decision tickets live in GitHub Issues on `asimog/mavrykx`. Solo repo, no triage vocabulary. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context, but vocabulary lives in `AGENTS.md` § Domain vocabulary and `docs/v1/02-domain-model.md`; there is no `GLOSSARY.md` or `docs/adr/`. See `docs/agents/domain.md`.

## House document style

- Title `# MavrykX — <name>` (the architecture doc is `# MavrykX — Detailed architecture`), then a `**Status:**` / `**Version:**` / `**Date:**` line.
- Terse declarative prose; lists for decisions and rules; tables only where comparison helps; mermaid for diagrams; British spelling.
- Docs state the design as it stands. They do not narrate amendments, reviews or prior implementations.
- Cross-link inside `docs/v1/`. New sources are cited inline where relevant.
- When adding or renaming a document, update the root `README.md` and the architecture doc.
