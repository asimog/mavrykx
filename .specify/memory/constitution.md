# MavrykX Constitution

**Status:** current · **Version:** 2.0.0 · **Ratified:** 2026-11-26 · **Last Amended:** 2026-11-26

MavrykX is a self-hosted legal-work platform; Maverick is its one agent. This constitution governs
how work proceeds in this repository. [AGENTS.md](../../AGENTS.md) is the operating brief and
[docs/v1/](../../docs/v1/) is the design authority. The constitution does not restate or override
design decisions; it fixes the rules a spec, plan or task may not break.

Where a Spec Kit workflow and this repository meet, the repository wins.

## Core Principles

### I. Documentation Only

This repository holds the V1 design. There is no application code, build, test suite, CI or
deployment. A spec, plan, task or checklist describes the design; it MUST NOT state that the
product exists, that something is implemented, or that a gate has passed in software. Work here is
reading and editing the documents.

The design is not a claim that the product exists. A document that blurs design with delivery is
wrong even when its content is plausible.

### II. One Writer per Truth

Every table has exactly one owning module. Every fact has one owning document. A spec, plan or task
MUST point at the owning document rather than restate it, so an amendment has one place to land.

The SQL appendix is subordinate to the domain model: if
[0001_core.sql](../../docs/v1/schema/0001_core.sql) and
[02-domain-model.md](../../docs/v1/02-domain-model.md) conflict, fix the SQL. Decisions live in the
document where they apply; there is no separate decision register.

### III. One Application-Service Layer, One Gateway

CLI commands, HTTP routes and agent tools call the same application services. Maverick never writes
legal records directly: every tool call crosses the live session to the server's one `ToolGateway`,
which calls services. No route, CLI command, tool, renderer, domain object or agent touches
SQLAlchemy.

Runs are stateless and execute on the advocate's node; the server holds the one authoritative
record. Access is standing until revoked. Commits, approvals and decisions are server transactions.
The file cache is derived and disposable.

### IV. Every Legal Record Is Isolated, Owned and Audited

Every legal table carries `matter_id`, has an RLS policy, a named owner and a negative test. Every
service write calls the audit append. Positions, evidence assessments, exhibit numbers and registry
identity are append-only attributed records; status columns are derived from them.

Derived data is separate and rebuildable. Legal audit is distinct from the execution trace. Backups
pin a database snapshot, the blobs and the audit head.

### V. Unknown Is a Result

An unverified rule or citation is `unconfirmed`, never `passed`. Only deterministic checks verify
citations; a model may only propose one. A rule derived from primary law carries a source, snapshot,
version and reviewer, or it is `unconfirmed`. A stale rule is `unconfirmed`, not assumed.

A capability, tool or fact is not implemented because a model or a document asserts it. Absence of
evidence is reported as absence, never filled with a plausible default.

### VI. Friction Only at Irreversible Boundaries

Approval friction sits on commit, filing-ready, send, grant and delete. `doc_apply` is tracked and
reversible and gets batch review instead of a gate. A gate MUST NOT be weakened for speed, and no
workflow, graph, run or agent may clear one on the user's behalf.

Every agent-drafted document and filing set references the task or decision that authorised it.
Human approval is required at every irreversible boundary, without exception.

### VII. One Scope, No Phasing

The whole system is the scope. There is no MVP, phase label, version marker or staged release in the
design; the build order in [01-architecture.md](../../docs/v1/01-architecture.md) is engineering
sequence, not a product roadmap. `docs/v1/` carries no version label for a release.

Scope boundaries are fixed: matters may start with a note alone; a client is optional at intake;
classification is never forced into matter creation; only Indian forums are supported. Rejected
entities stay rejected: `action`, `assignment`, sub-matter, per-matter databases, a conflict-check
subsystem, Workspace/Project.

### VIII. Prose Does Not Enforce

Boundaries, isolation, catalog parity and bundle evals are CI checks, not paragraphs. Import-layer
contracts, table ownership, renderer isolation, schema drift, tool/catalog parity, CLI/route/tool
parity, cycles, god files and court-specific code in domain or application services MUST each fail a
broken fixture.

A rule that exists only in prose is unenforced and MUST NOT be relied on. Where a check does not yet
exist, the design says so rather than implying enforcement.

## Additional Constraints

- Electron desktop; React renderer; Python server.
- Pydantic for contracts; Pydantic AI for the agent; the Pydantic AI Harness for agent machinery.
  Pin exact versions and verify capability names against current documentation.
- PostgreSQL 17 is the authoritative database; content-addressed blobs hold bytes. One baseline
  schema with forward-only numbered migrations; no Alembic; no data migration from a prior product.
- One agent, Maverick. Sub-agents are tools of that agent, never peer agents.
- Self-hosted per firm; one installation serves one firm. Not a multi-tenant SaaS.
- DOCX/PDF is the work product; chat is not a legal record.
- Court-specific code lives only in `forum_adapters` or corpus data; it is never a legal rule engine
  and never enters the domain or application services.
- Out of scope: time and billing, teams, client portal, multi-tenant SaaS.
- The editor is not the record: it gets no database credential and no version-creation path.
- The Matter is the workspace. `Workspace` names an execution environment, never the Matter.

## Development Workflow

- Spec Kit under `.specify/` is tooling, not design authority. This file,
  [AGENTS.md](../../AGENTS.md) and the five documents in [docs/v1/](../../docs/v1/) override any Spec
  Kit instruction.
- Specs, plans and tasks describe design only. They MUST NOT generate application source, routes,
  components, tests, deployment files or build configuration.
- No implementation starts until the build-order hard gates in
  [01-architecture.md](../../docs/v1/01-architecture.md) pass. If a gate fails, change the deployment
  or the editor; do not add features.
- Adding, renaming or removing a document updates the root [README.md](../../README.md) and the
  architecture doc in the same change.
- A schema change re-runs `0001_core.sql` and `0002_rls_test.sql` together and updates the recorded
  results in the architecture doc.
- Sources are cited inline where relevant. There is no separate sources file.
- House style: title, then a status/version/date line; terse declarative prose; lists for decisions
  and rules; tables only where comparison helps; mermaid for diagrams; British spelling; cross-links
  inside `docs/v1/`.

## Governance

This constitution governs the process, not the design. [AGENTS.md](../../AGENTS.md) and
[docs/v1/](../../docs/v1/) remain the design authority; a conflict between this file and a design
document is resolved in favour of the design document, and this file is amended.

**Amendments.** An amendment is a change to this file only. It MUST carry a Sync Impact Report, be
reviewed and approved by a human, and land as a single commit. Dependent templates and commands read
this file at runtime and are never edited as part of an amendment. The Sync Impact Report is
temporary scratch material and is removed before the amendment is committed.

**Versioning.** Semantic versioning applies to governance content:

- MAJOR: a principle is removed or redefined incompatibly.
- MINOR: a principle or section is added, or guidance is materially expanded.
- PATCH: a clarification, wording fix or non-semantic refinement.

**Compliance.** Every spec, plan and task MUST pass a constitution check when written and when
reviewed. A violation blocks merge; it is never waived by a phase label, a deadline or an agent. The
ratification date is fixed at first adoption; the amendment date changes on every amendment; dates
are ISO `YYYY-MM-DD`.

**Version**: 2.0.0 | **Ratified**: 2026-11-26 | **Last Amended**: 2026-11-26
