# MavrykX — Application, agent and data

**Status:** current · **Version:** v1 · **Date:** 2026-11-26

This document owns the application services, the one agent, the tool gateway, workflows, the CLI, data, documents, security and audit. The module map and stack are in [01-architecture.md](01-architecture.md); the entities and definitions are in [02-domain-model.md](02-domain-model.md).

---

## 1. Application services

Application services own the use cases. A route, CLI command, tool or agent never owns a business rule.

- Every service method takes a `MatterScope` where the record is Matter-bound.
- A service calls another module through a public contract, never through its repository or tables.
- A service write emits an audit event.
- A service read of a Matter checks matter membership, walls and resource grants.
- A transaction belongs to the use case, not to a route or a tool.
- Unknown is a result; a service does not return the closest match.

The public surface per module is `api.py`, `contracts.py` and `service.py`. The private surface is `models.py`, `repository.py`, `mappers.py`, `internal/`, migrations, SQL and tests.

---

## 2. Tool execution: one agent-tool path

Every **agent tool call** goes through the one `ToolGateway`.

```text
Maverick / sub-agent / server job
        ↓
ToolGateway
  bundle → run scope → permission → policy/egress → approval → idempotency
        ↓
one application service
        ↓
PostgreSQL transaction
        ↓
agent_event + audit_event
        ↓
validated result
```

**What “one path” means.**

- One execution pipeline for agent tools.
- Not one giant function.
- Not “every surface must pretend to be an agent.”

**What it does not mean.**

- The CLI and FastAPI are not agent runs. They call the same application services with their own session auth and route validation.
- The common authority is the service. The gateway is the agent’s door; CLI and HTTP are other doors.
- A tool that calls a service directly would reimplement scope, permission, approval, idempotency and audit.
- A route that calls a repository directly would bypass the service.

**Rules.** Unknown tool → deny. Tool not in the selected bundle → deny. Permission not held → deny. Matter policy narrower → deny. Approval stale → deny. Tool error fails the step, not the Matter. Every call has an operation id; a replay returns the prior result.

---

## 3. Tools, Harness capabilities and bundles

- **Tool** — one typed callable: name, input schema, output schema, side effects, permissions. The tool catalog is the one definition of a business action.
- **Harness capability** — a Pydantic AI composable unit that may add tools, instructions, hooks, state and lifecycle. Examples: `Skills`, `Memory`, `AskUser`, `SubAgents`, `StepPersistence`, `ToolSearch`, `Compaction`.
- **Bundle** — a versioned selection of tools, instructions, sub-agent tools, permissions, budget, evals and owner.
- **Legal capability pack** — MavrykX-authored Harness capabilities that wrap legal services and constraints.

A tool is not a Harness capability. A Harness capability is not a business action. A bundle is not a folder of prompts.

**Progressive disclosure.** The tool catalog may be large; the active surface is small.

- A bundle selects the capabilities and tools a run may use.
- A tool outside the bundle is denied even if the model names it.
- Use Harness `ToolSearch` / `ToolBridge`, `defer_loading`, `Skills`, `ToolOutputLimits` and `Compaction`.
- A hidden tool is not an access-control boundary. The gateway and RLS enforce access.
- The UI shows lawyer-language steps, not raw tool names.

---

## 4. The one agent

Maverick is one agent configuration:

- one system prompt lineage;
- bundle selectors by Matter, step and document type;
- model policy: provider, model, reasoning, fallback, budget;
- typed output for the run.

There are no separate chat, drafting, research or intake agents. Different work is different bundles, skills, workflows and context.

**Sub-agents** are tools of the one agent:

- scope is the intersection with the parent;
- no commit/approve/file/send rights;
- no user channel;
- depth cap 2;
- traced as child runs.

**Harness capabilities used:**

- Skills, SubAgents, Dynamic Workflow (read-only fan-out), Planning, Memory, Compaction, Step Persistence, Guardrails, Goal, budgets, model routing, tracing.
- `AskUser`, deferred tools and tool approval for interaction.
- `ToolCallJudge` may block; `ApprovalReviewer` is never enabled for legal actions.
- `Peers` and `CapabilityCreation` are not enabled.

**What the Harness does not own:** Matter access, document identity, approvals, audit, legal records. A Harness Workspace is an execution environment; the Matter is not a Workspace.

**AgentComposition** is the composition root that builds the Pydantic AI `Agent` from the Harness capabilities and the legal pack. It is not a second harness.

---

## 5. Context assembly

The context package is a record, not a transient string. It is persisted before the model is called.

- Start with `MatterScope`: Matter, user, grant, wall, bundle.
- Add system policy, bundle instructions, skill text, task/step instruction.
- Add the Matter spine: parties, proceedings, next dates, open decisions, open gates.
- Add only the records the bundle/skill/task declares.
- Add explicit references (document version, conversation, research result) after their own access check.
- Add matter-scoped retrieval only; no global index.
- Fit by priority; record truncation and exclusions.
- Persist the manifest: ids, versions, hashes, Matter, inclusion/exclusion reason and token counts.

**Private conversations.** A private conversation is included only for its owner. A shared conversation only for a participant. A Matter conversation for members, subject to walls. A message link to a document is not a grant.

**Resumed runs.** Replay the exact package, then revalidate pins. A superseded document version, stale rule or changed approval is marked `stale`/`unconfirmed`; do not silently rebuild.

---

## 6. Approvals and gates

- `AskUser` and deferred tools are the interaction: ask, pause, resume.
- `LegalApproval` is the record: authenticated human, Matter role, exact subject hash, action, rationale, time, expiry, step-up.
- A `resume[]` is transport; it is validated against stored history before any tool runs.
- A model never approves a legal action.
- Approval friction sits on irreversible boundaries: commit, filing-ready, send, grant, delete.
- `doc_apply` is tracked and reversible; batch review in the inbox. Do not add step-up per apply.
- A changed subject makes the approval stale.
- An agent cannot approve its own work.

**Gate kinds:** Matter open, document approve, filing ready, rule publish, access grant, deletion. A gate blocks until a human clears it against frozen evidence.

---

## 7. Workflows

`pydantic-graph` is the workflow runtime. A workflow is a typed graph over a state object.

- A node may call a service, run Maverick, run a deterministic check or wait at a human gate.
- `workflow_definition` / `workflow_version` / `workflow_run` / `workflow_step` are the records.
- A **playbook** is a kind of workflow definition, not a second runtime.
- A **workflow creator** edits a validated graph spec; it does not execute arbitrary Python.
- A workflow is deterministic orchestration, not an agent. The Harness `Dynamic Workflow` capability is a separate agent fan-out primitive; name it in full.
- A legal gate is a workflow node; the agent cannot clear it.
- A run pins the definition version.
- `job` is the durable queue: type, payload, attempts, `run_at`, `locked_by`, `locked_at`, `lease_expires_at`, `status`, `idempotency_key`. `NOTIFY` wakes a worker on commit; a rolled-back request queues nothing.

---

## 8. CLI and tools

Typer is the business CLI. `clai` is Pydantic AI’s chat client, not the business CLI.

- The CLI calls application services. No business logic, no SQLAlchemy.
- `mavrykx` commands cover Matter, membership, conversations, messages, files, context, tasks, research, review, documents, sessions, runs, nodes, classification, forum sync, browser, corpus, case law, library, Research Studio and workflows.
- The tool catalog generates the CLI command, HTTP operation, Pydantic AI tool and docs. A tool in two places is a defect.
- `clai` / `mavrykx chat` is optional conversational access; a model-mediated prompt cannot replace a deterministic command, typed flags, exit codes or a security action.

**Core commands:**

`matter create|member add|member revoke|wall raise` · `conversation create|share` · `message post` · `file upload|get` · `context select` · `classification propose|confirm` · `forum adapter sync` · `browser open|handoff` · `task create|assign|attach` · `research submit` · `review decide` · `document get|propose|compare|apply|accept|reject|comment` · `document session open|status|close` · `corpus ingest` · `case-law search` · `library publish|grant` · `research studio create|run` · `workflow create|publish|run` · `run start|status|cancel` · `node register|status|revoke` · `audit verify|export`.

**Shared errors:** `MATTER_ACCESS_DENIED`, `RESOURCE_ACCESS_DENIED`, `DOC_STALE_BASE`, `DOC_STALE_TARGET`, `DOC_SESSION_ACTIVE`, `DOC_SESSION_REVOKED`, `PROPOSAL_STALE`, `PROPOSAL_CONFLICT`, `RUN_LEASE_LOST`, `RUN_ACCESS_REVOKED`, `EFFECT_UNCERTAIN`, `APPROVAL_STALE`, `IDEMPOTENT_REPLAY`.

---

## 9. Data

### PostgreSQL

- One database, one baseline schema, one owner per table.
- Every legal row carries `matter_id` and RLS.
- The app role has no `BYPASSRLS`; the table owner is forced through RLS.
- `app.user_id` is set per transaction with `set_config(..., true)`.
- Immutable: document versions, audit events, published rules.
- Derived: text, embeddings, read models; rebuildable.
- JSONB only for open-ended payloads, not fields the product queries or constrains.
- Postgres FTS + pgvector; no separate search/vector database.

### Blobs

- Content-addressed by sha256; one copy per content.
- Write to temp, fsync, verify, rename; insert metadata and version in one transaction.
- Reference-counted; GC only unreferenced and never during legal hold.
- Blob path is derived from the hash; a read verifies it.

### Documents

- Server owns identity, versions, anchors, permissions, approvals and commit.
- The editor owns pixels. `docx-core` is read/verify only. The builder is the sole agent/offline DOCX mutator.
- Every edit carries expected text and base hash; a moved base fails `DOC_STALE_BASE`/`DOC_STALE_TARGET`.
- Human edits create a new immutable version. A live session checkpoint is derived; a crash can promote it to an unapproved `editor_recovery` version.
- Tracked changes by agents use `w:ins`/`w:del` authored `maverick:agent:<run_id>`; a human author is never swapped.
- A version with pending changes is not approvable.

### Live editing

- Firm profile: Euro-Office DocumentServer. Docs API primary; WOPI fallback.
- `editing_session.id` is the Docs API key; one active session per document.
- Session fence refuses out-of-session commits.
- Presence/cursors are editor state; not records.
- Revocation calls `drop` and rejects the next callback.

### Primary law and case law

- `corpus` owns court rules, statutes, laws, regulations and notifications. `case_law` owns judgments, authorities, citations and treatment.
- A source enters `source`; a snapshot is content-addressed; a human verifies; an amendment is a new version with `supersedes_id`.
- A stale rule or authority says `unconfirmed`, never current.
- Citation verification is deterministic: authority, form, pinpoint, quote, currency, treatment.
- The corpus pipeline never ingests case law; the case-law module never ingests statutes.

### Library

- Firm templates, precedents, checklists and guidance.
- Admin publishes and grants access.
- A template is read-only to drafting until a new version is published.
- A library item is not primary law and not Matter evidence.

### Audit

- Append-only, hash-chained legal/security events.
- Who, what, when, which Matter, which subject, why, evidence reference.
- Immutable; app role can append via function and read, not update/delete.
- Retention: life of Matter + 7 years; legal hold blocks deletion.
- Signed daily anchor; `mavrykx audit verify`; signed export.
- Legal audit ≠ execution trace. The trace holds prompts, tools, model, cost, latency.
- The chain hashes the complete event, including `at`, `seq`, `id` and the payload. A changed timestamp breaks the chain.

---

## 10. Security

- Local accounts + TOTP + server sessions + device keys; OIDC optional.
- Argon2id passwords; breached-password check.
- Step-up auth for commit, filing-ready, send, grant, delete.
- RBAC for firm functions; Matter grants; walls; resource grants.
- Agent inherits the launching user, intersected with the bundle; no wider access.
- A shared conversation never widens document access.
- Egress denied by default; per-capability allowlist; credential injection; leak scan.
- Tool trust tiers: internal in-process; reviewed worker; untrusted WASM/subprocess. MCP is untrusted until reviewed.
- Encrypted backups; dry-run restore; apply requires approval.
- TLS mandatory; self-signed only with pinning.
- What is not claimed: compliance with any standard. Controls, not certification.

---

## 11. Data and agent acceptance

- A service write has an audit event; a broken fixture fails the check.
- A cross-Matter API/search/embedding/export returns nothing.
- A wall hides the Matter everywhere.
- A tool outside the bundle is denied.
- A stale approval rejects a commit.
- A prompt injection cannot call a human-only action.
- A document version is immutable; a changed subject resets approval/readiness.
- A corpus instrument has source/snapshot/version/reviewer; a stale one is `unconfirmed`.
- A case-law quote/pinpoint verifies deterministically.
- A library item is admin-published and invisible without a grant.
- A workflow run pins its definition; a replay does not duplicate a side effect.
- An agent run has a scope, context package and budget.
- The audit chain verifies; a tampered row fails.
