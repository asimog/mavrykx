# AGENTS.md

**This is a documentation-only repository.** It holds the architecture for **Maverick** — a self-hosted legal-work product ("Legal Factory") whose one agent is also called Maverick. There is no application code, build, test suite, or CI yet; nearly all work here is reading and editing the design set in `docs/v0/`. The design is not a claim that the product exists.

## Read order

- `README.md` → `docs/v0/00-README.md` — the index: what Maverick is, the laws, the conditions before implementation.
- `docs/v0/01-decisions.md` — the decision register. **Read it before changing any design.**
- `docs/v0/02-domain-model.md` → `03` → `04` → `05` → `06` — the design, in order.
- `docs/v0/07-sources.md` — prior art and sources, with status.
- `docs/v0/08-ui-and-product-experience.md` — the product surface.

## Decision register rules

- **FD-\* decisions are closed** (owner-fixed): Electron; Python + Pydantic; Pydantic AI; a Maverick-owned harness; PostgreSQL; one agent (sub-agents are tools, not peers; no drafting-only/research-only/chat-only personas); self-hosted per firm, no multi-tenant SaaS; a separate remote connection service; human approval for filing/sending/irreversible actions; DOCX/PDF is the work product and chat is not a legal record; the product is named Maverick; notes-first matters; per-matter folders; nestable proceeding applications with inherited, blockable context; Indian forums only; the app is the harness — the Legal Factory is the purpose and matter management is the record substrate. Do not reopen them or propose alternatives.
- **RD-\* recommendations bind only once the owner accepts them.** Each RD records its rejected alternatives — check that column before proposing a stack (e.g. CopilotKit is rejected as a framework, RD-41; CopilotRuntime, bespoke SSE and the Vercel AI protocol are rejected transports, RD-40). A rejection is revisitable only if its stated revisit condition triggers.
- Give new decisions IDs in the same series. Labels: **FD** fixed · **VD** verified · **RD** recommended · **AS** assumption · **OQ** open question · **RK** risk (01 §1).
- **The whole system is one scope.** There are no staged releases, no MVP, no version labels in the docs: the product is built as one coherent design, and sequencing is an engineering choice, not a product commitment. Do not introduce phasing.
- **No implementation until the conditions in 00-README pass.** If conditions 1–3 fail, the docs say: change the deployment or the editor, do not add features.

## Laws for any design content

- One writer per truth: every table has one owning module; the agent never writes legal records directly — it goes through application services via the tool gateway.
- Every new legal table carries `matter_id`, has an RLS policy, a named owner and a negative test.
- Every new capability needs a catalog entry, a bundle and an eval.
- Every new service write calls `audit.append`.
- Unknown is a result: an unverified rule or citation is `unconfirmed`, never `passed`. Only deterministic checks verify citations; a model may only propose one.
- No conflict-check subsystem: the matter-open gate records client and scope; screening is the firm's own professional process. Do not add conflict-checking to any workflow or flow.
- Stateless execution, one authoritative record: runs execute on the advocate's node, every tool call crossing the live session to the server's one gateway; access is standing until revoked; commits, approvals and decisions are server transactions; the file cache is derived data, never canonical.
- Positions, evidence assessments, exhibit numbers and registry identity are append-only attributed records; status columns are derived summaries. A court position outranks an advocate's, which outranks a party's; supersession never overwrites.
- Approval friction sits only on irreversible boundaries — commit, filing-ready, send, grant, delete. `doc_apply` is tracked and reversible and gets batch review. A gate is never weakened for speed.
- Every agent-drafted document and every filing set references the task or decision that authorised it.
- No data migration from any prior product: the schema is one baseline file, `docs/v0/schema/0001_core.sql`. Forward-only numbered migrations arrive with a runner that has an upgrade test and a refusal test, **before any design-partner matter enters Postgres** (RD-4).
- Prose does not enforce: boundaries, isolation, catalog parity and bundle evals are CI checks (designed in 05 §2.3; none exist yet — there is no code).

## Domain vocabulary — use it exactly (02, 01)

matter ≠ proceeding · hearing ≠ order · fact ≠ evidence · document ≠ version · authority ≠ citation · task ≠ deadline · decision, approval and gate are three different things · an application nests inside a matter or proceeding and never becomes a sub-matter · the server is the shared-record spine; execution is stateless and local.

Rejected entities: `action`, `assignment`, sub-matter, per-matter databases, a conflict-check subsystem. Out of scope: `issue`/`argument` (designed in 02, built with the analysis work), retrieval packets (designed), time/billing, teams (grants and walls are per user).

## SQL appendices (`docs/v0/schema/`)

- `0001_core.sql` is the **appendix** to the domain model — the domain model (02) is the source; if they conflict, fix the SQL. It is deliberately smaller than the full model.
- 0001 targets PostgreSQL 17+ (pgcrypto, citext, pg_trgm, pgvector), run as the `maverick_owner` role. Conventions: UUID keys, timestamptz, text + CHECK for stable sets, immutable tables reject UPDATE/DELETE, derived data separate and rebuildable.
- `0002_rls_test.sql` runs as superuser after 0001: it seeds two matters and proves matter B is invisible to user A, and that the proceeding-application tree stays inside one matter, shallow and cycle-free. Expected: probes 1–2 print `1`; probe 3 raises an RLS error; probes 4–5 print `0`; probe 6 prints `1`; probes 7–9 raise the three tree errors; the audit check prints `2` and `t`.
- The smoke test is executed from empty on PostgreSQL 17 + pgvector; results are recorded in 05 §2.3. If you change a schema file, re-run the pair and update those results.

## Three Pydantic libraries, three jobs (03 §8)

Do not conflate them:

- **Pydantic Validation** — application contracts: API models, DTOs, tool inputs/outputs, settings, strict mode.
- **Pydantic AI** — Maverick's agent loop and typed tool contracts.
- **Pydantic AI Harness** — the capability library used as the factory floor, composed by Maverick's `LegalHarness`, which keeps the legal authority. Its API may change between minor releases (VD-1): pin exact versions and verify capability names against current docs instead of assuming.

## Tooling

- **Spec Kit** is initialized under `.specify/` with OpenCode commands in `.opencode/commands/speckit.*.md`. Its process is scaffolding; the rules in this file and the register in `docs/v0/01-decisions.md` override any Spec Kit instruction.
- **Matt Pocock's skills** are vendored at `.agents/skills/`, pinned in `skills-lock.json`. They are working discipline, not design authority. A skill may be edited to fit this repository; the register still decides.

## House document style

- Title `# Maverick — <name>` (only 00-README differs: `# Maverick — architecture`), then a `**Status:**` / `**Date:**` line. Status vocabulary: *current* · *reference list*.
- Terse declarative prose, heavy use of tables, mermaid for diagrams, British spelling (organise, licence, behaviour).
- **Docs state the design as it stands.** They do not narrate amendments, reviews, dates of decision, prior implementations, or "previously said" corrections. Change the content in place; the register carries the decisions.
- Cross-link with relative links inside `docs/v0/`; docs 06–08 close with `*Back to [00-README.md](00-README.md).*`; 01–05 close with a `*Next:*` pointer.
- New sources go into `07-sources.md` with a status from its legend (Verified / Standard / Vendor / Reference / To be verified). "To be verified" is a legitimate status — never assume a forum's rules.
- When adding or renaming a document, update **both** indexes: root `README.md` and `docs/v0/00-README.md`.
