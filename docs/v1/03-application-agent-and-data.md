# MavrykX — Application, agent and data

**Status:** current · **Version:** v1 · **Date:** 2026-11-28

This document owns the application services, the one agent, the tool gateway, workflows, the CLI, data, documents, security and audit. The module map and stack are in [01-architecture.md](01-architecture.md); the entities and definitions are in [02-domain-model.md](02-domain-model.md).

The build order is CRM first, Maverick second. Steps 1–6 deliver the legal CRM and shared Matter workspace through these services. Step 7 wires Maverick to the same services through the one gateway. No CRM service depends on a model, a bundle or a run.

---

## 1. Application services

Application services own the use cases. A route, CLI command, tool or agent never owns a business rule.

- Every service method takes a `MatterScope` where the record is Matter-bound and an `Actor` (the initiating human).
- A service calls another module through a public contract, never through its repository or tables.
- A service write emits an audit event.
- A service read checks firm-admin access or Matter membership, and a restricted-document grant.
- A service write checks the expected revision (or document base version/hash) and never applies last-write-wins.
- A transaction belongs to the use case, not to a route or a tool.
- Unknown is a result; a service does not return the closest match.

The public surface per module is `api.py`, `contracts.py` and `service.py`. The private surface is `models.py`, `repository.py`, `mappers.py`, `internal/`, migrations, SQL and tests.

### CRM services and the future harness

These are the service groups the CRM implements first. The names are contracts, not a second registry; the operation catalog remains the one definition of each action.

| Group | Service surface |
|---|---|
| `identity` | Firm bootstrap, user invite, membership role, session and device. |
| `access` | Matter member add/revoke with `edit` or `view`, restricted-document resource grant, the one `access.can(actor, resource, action)` policy. |
| `contacts` | Contact and client create/update; a client may own many Matters. |
| `matter` | Matter open/update/close, party add, note create/edit/archive. |
| `work` | Task create/assign/update/complete, deadline create/confirm, appointment create/update/cancel. |
| `documents` | Section create/rename/move/archive, document create/upload, version list/compare/restore, edit lease open/save/close/revoke, proposal create/apply. |
| `harness` | Conversation create/share, message post; no legal record. |
| `approvals` | Review submit, comment, approve/return; gate and decision. |
| `audit` | Append on every write; list and verify. |

**Contract rules.**

- Every Matter-bound call takes `MatterScope` and an `Actor`. The actor is always a human user; an agent call carries the initiating user and, where applicable, the run.
- A write takes an opaque `expected_revision` (a document takes `base_version_id` and `base_hash`). A mismatch is `RESOURCE_STALE`; the service never applies last-write-wins.
- Every mutation declares `patch` or `replace`. A replace requires a precondition (revision, version id or timestamp); a missing declaration fails the operation check.
- A write takes an idempotency key. A replay returns the prior result.
- A write emits an audit event in the same transaction. A read checks firm-admin access or Matter membership, and the restricted-document grant.
- The contract is Pydantic at the boundary. Domain entities stay plain Python.
- The future harness calls these services through `ToolGateway`; it does not get a parallel API, a direct repository or a wider scope. `human_only` operations (approve, commit, filing, send, grant, delete) are never model tools.
- The first harness-facing reads are `matter.get`, `workspace.list`, `document.get`, `document.history`, `note.list`, `task.list`, `event.list`, `conversation.list` and `research.get`. The first proposals are `note.create`, `task.create` and `document.propose`. Submission is human; approval is human-only.
- A CRM operation may ship before its tool catalog entry. The tool entry is added in step 7, with the bundle and eval, not before the service exists.

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

**Dispatch before execution.** The gateway appends a `dispatched` agent event before it calls the service; if that write fails, the tool does not run. It appends `completed` or `failed` after. The trace carries refs, hashes, model and cost, not raw legal text or tool arguments.

The gateway is wired in step 7. Until then the same operations are exercised through the API and CLI. The CRM is not a set of agent tools with a UI attached; the services are the product, and the agent is a later caller.

---

## 3. Tools, Harness capabilities and bundles

- **Tool** — one typed callable: name, input schema, output schema, side effects, permissions. The operation catalog is the one definition of a business action; the tool catalog is its agent-facing subset.
- **Harness capability** — a Pydantic AI composable unit that may add tools, instructions, hooks, state and lifecycle. Examples: `Skills`, `Memory`, `AskUser`, `SubAgents`, `StepPersistence`, `ToolSearch`, `Compaction`.
- **Bundle** — a versioned selection of tools, instructions, sub-agent tools, permissions, budget, evals and owner.
- **Legal capability pack** — MavrykX-authored Harness capabilities that wrap legal services and constraints.

A tool is not a Harness capability. A Harness capability is not a business action. A bundle is not a folder of prompts.

The tool catalog is derived from the CRM operation catalog in step 7. A tool that has no service behind it is a defect. A service that is not in any bundle is still reachable through HTTP and the CLI; hiding a tool is not access control.

**Progressive disclosure.** The tool catalog may be large; the active surface is small.

- A bundle selects the capabilities and tools a run may use.
- A tool outside the bundle is denied even if the model names it.
- Use Harness `ToolSearch` / `ToolBridge`, `defer_loading`, `Skills`, `ToolOutputLimits` and `Compaction`.
- A hidden tool is not an access-control boundary. The gateway and RLS enforce access.
- The UI shows lawyer-language steps, not raw tool names.

---

## 4. The one agent

Maverick is one agent configuration, built in step 7 on the completed CRM services:

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

- Start with `MatterScope`: Matter, user, Matter access, bundle.
- Add system policy, bundle instructions, skill text, task/step instruction.
- Add the Matter spine: client, parties, proceedings, sections, next dates, open tasks, open reviews, open decisions and open gates.
- Add only the records the bundle/skill/task declares.
- Add explicit references (document version, note, task, event, conversation, research result) after their own access check.
- Apply the initiating user's Matter access. A Matter member reads every note, task and conversation in the Matter. A restricted document is excluded without a grant, except for the firm admin.
- Add matter-scoped retrieval only; no global index.
- Fit by priority; record truncation and exclusions.
- Persist the manifest: ids, versions, hashes, Matter, inclusion/exclusion reason and token counts.

**Conversations.** A conversation is Matter-wide. Every Matter member reads it. A message link to a document is not a grant.

**Resumed runs.** Replay the exact package, then revalidate pins. A superseded document version, stale rule or changed approval is marked `stale`/`unconfirmed`; do not silently rebuild.

**Output scope.** Agent output that embeds Matter content carries the source Matter and version ids. It is stored and rendered only while the reader can still read those sources; a lost grant or a cross-Matter copy does not inherit the output. A citation ref is minted by the run; an unminted ref is rendered as unresolved, never as a source.

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

**Review and approval are different.** A review is the supervising lawyer's decision on submitted work; an approval is the hash-bound permission for one legal operation. A submission composes a task, a document version, an approval, annotations and a notification. A return rejects the approval, reopens the task and leaves the version intact; the next attempt is a new version. Only a firm admin or a lawyer with Matter `edit` access decides; where another eligible reviewer exists, the author does not decide their own submission. A one-person firm may self-approve, marked in the audit.

**Gate kinds:** Matter open, document approve, filing ready, rule publish, access grant, deletion. A gate blocks until a human clears it against frozen evidence.

**Tool policy.** Every tool declares a policy kind: internal read, mutation, external call, public-official source, or scope expansion. Unknown or missing policy fails closed. A gated tool pauses the run with a typed decision.

**Standing grants.** A grant has scope `conversation` or `always`, a tool or connector, and a policy: `grantable`, `approve-once` or `never-auto`. A grant removes the gate only where the tool policy allows it. Delete, grant, filing, send and approval are never `grantable`. A sub-agent runs only ungated tools; every gated call returns to the top-level run as a proposal.

---

## 7. Workflows

`pydantic-graph` is the workflow runtime. A workflow is a typed graph over a state object.

- A node may call a service, run Maverick, run a deterministic check or wait at a human gate.
- `workflow_definition` / `workflow_version` / `workflow_run` / `workflow_step` are the records.
- A **playbook** is a kind of workflow definition, not a second runtime.
- A **workflow creator** edits a validated graph spec; it does not execute arbitrary Python.
- A workflow is deterministic orchestration, not an agent. The Harness `Dynamic Workflow` capability is a separate agent fan-out primitive; name it in full.
- A legal gate is a workflow node; the agent cannot clear it.
- A review gate raises a review task; settling the gate settles the task, and completing the task settles the gate.
- A run pins the definition version.
- `job` is the durable queue: type, payload, attempts, `run_at`, `locked_by`, `locked_at`, `lease_expires_at`, `status`, `idempotency_key`. `NOTIFY` wakes a worker on commit; a rolled-back request queues nothing.

---

## 8. CLI and tools

Typer is the business CLI. `clai` is Pydantic AI’s chat client, not the business CLI.

- The CLI calls application services. No business logic, no SQLAlchemy.
- `mavrykx` commands cover firm, user, client, contact, Matter, membership, section, note, task, assignment, event, conversation, message, review, documents, sessions, context, research, runs, nodes, classification, forum sync, browser, corpus, case law, library, Research Studio and workflows.
- The tool catalog generates the CLI command, HTTP operation, Pydantic AI tool and docs. A tool in two places is a defect.
- `clai` / `mavrykx chat` is optional conversational access; a model-mediated prompt cannot replace a deterministic command, typed flags, exit codes or a security action.

**Core commands:**

`firm init` · `user invite|disable` · `client create|update` · `contact create|update` · `matter create|member add|member revoke|close` · `section create|rename|move|delete` · `note create|edit|delete` · `task create|assign|update|complete` · `event create|update|cancel` · `conversation create|share` · `message post` · `file upload|get` · `document get|submit|compare|restore` · `document session open|save|close|revoke` · `document propose|apply|accept|reject|comment` · `review submit|comment|decide` · `context select` · `classification propose|confirm` · `forum adapter sync` · `browser open|handoff` · `research submit` · `corpus ingest` · `case-law search` · `library publish|grant` · `research studio create|run` · `workflow create|publish|run` · `run start|status|cancel` · `node register|status|revoke` · `audit verify|export`.

**Shared errors:** `MATTER_ACCESS_DENIED`, `RESOURCE_ACCESS_DENIED`, `RESOURCE_STALE`, `DOC_STALE_BASE`, `DOC_STALE_TARGET`, `DOC_SESSION_ACTIVE`, `DOC_SESSION_REVOKED`, `EDIT_LEASE_HELD`, `PROPOSAL_STALE`, `PROPOSAL_CONFLICT`, `REVIEW_STALE`, `RUN_LEASE_LOST`, `RUN_ACCESS_REVOKED`, `EFFECT_UNCERTAIN`, `APPROVAL_STALE`, `IDEMPOTENT_REPLAY`.

---

## 9. Data

### PostgreSQL

- One database, one baseline schema, one owner per table.
- Every legal row carries `matter_id` and RLS.
- The app role has no `BYPASSRLS`; every app query is subject to the policy. The migration owner reads `document` without FORCE for the access function, to prevent function recursion.
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
- Every save carries the edit lease, base version and base hash; a moved base fails `DOC_STALE_BASE`; a lost lease fails `DOC_SESSION_REVOKED`.
- Sequential editing creates one immutable version per save. There is no live buffer, server checkpoint or `editor_recovery` version in V1.
- Tracked changes by agents use `w:ins`/`w:del` authored `maverick:agent:<run_id>`; a human author is never swapped.
- A version with pending changes is not approvable.

### OCR

- Local by default: `ocrmypdf` for searchable PDFs, `pytesseract` for images, Tesseract 5.x with English and Indic language data pinned with the installer.
- A hosted engine sits behind the same `OcrEngine` port and is off unless a firm opts in.
- OCR runs in the worker; derived text carries the source hash and a confidence, and never replaces the original.

### Email

- Deferred. When it becomes a record, `aiosmtplib` sends and `imap-tools` ingests; raw messages and attachments are blobs, metadata is a record.

### Document editing

- Local Windows-native Euro-Office: the embedded frontend and `x2t`; saves go to the MavrykX API. No `DocService`, hosted DocumentServer or Docker process is in the V1 path.
- The edit-lease and base-bound save contract is owned by [04-shared-workspaces-and-collaboration.md](04-shared-workspaces-and-collaboration.md) §6. The data consequences are one immutable version per save, a document row lock, a unique `(document_id, version_no)`, no live buffer and no server checkpoint.
- Revocation marks the lease `revoked` and rejects the next save or tool call. Presence, cursors and typing are not modelled; the workspace change feed carries only an invalidation and a revision.

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
- Every workspace mutation emits an event, not only document versions and legal records: section, note, task, assignment, event, conversation, message, document, review, approval and deletion.
- Who, what, when, which Matter, which subject, why, previous/next revision or hash, evidence reference.
- Performer type is `user`, `agent`, `system` or `service`. A service is a named connector or MCP; `actor_ref` names it. Trigger is `direct`, `delegation` or `schedule`. The audit event stores the performer, trigger, run, initiating user, approval status and approver as columns. The JSONB payload carries evidence and detail.
- A document event names the version and hash. A review event names the submitted hash and decision. A deletion names what was removed or archived.
- Immutable; app role can append via function and read, not update/delete.
- Retention: life of Matter + 7 years; legal hold blocks deletion.
- Signed daily anchor; `mavrykx audit verify`; signed export.
- Legal audit ≠ execution trace. The trace holds prompts, tools, model, cost, latency.
- The chain hashes the complete event, including `at`, `seq`, `id` and the payload. A changed timestamp breaks the chain.

---

## 10. Security

- Local accounts + TOTP + server sessions + device keys; OIDC optional.
- Argon2id passwords (`argon2-cffi`); TOTP (`pyotp`); breached-password check.
- Sessions are opaque 256-bit tokens stored hashed in `session`; revocation deletes the row. JWTs are only for short-lived document URLs and the signed local-editor config.
- Step-up auth for commit, filing-ready, send, grant, delete.
- Firm roles `admin`, `lawyer`, `staff`, `intern`; Matter access `edit` or `view`. A firm admin reads every Matter and assigns Matter access. A non-member reads no Matter.
- Every Matter member reads every note, task, conversation and message in the Matter. There are no private resources. Restricted documents need a grant, and the grant covers every related document row. A firm admin does not need the grant.
- The baseline enforces this model. There is no ethical wall and no conflict-check subsystem.
- Agent inherits the launching user, intersected with the bundle; no wider access.
- A shared conversation never widens document access.
- V1 has no hosted DocumentServer, no Docker dependency and no real-time co-editing; the editor is local and saves through the API.
- Egress denied by default; per-capability allowlist; credential injection; leak scan.
- Tool trust tiers: internal in-process; reviewed worker; untrusted WASM/subprocess. MCP is untrusted until reviewed.
- Encrypted backups; dry-run restore; apply requires approval.
- TLS mandatory; self-signed only with pinning.
- What is not claimed: compliance with any standard. Controls, not certification.

---

## 11. Data and agent acceptance

- A service write has an audit event; a broken fixture fails the check.
- A workspace write without an audit event fails the check, whether the resource is a document, note, task, event, conversation or section.
- A cross-Matter API/search/embedding/export returns nothing, for every workspace resource type.
- A firm admin reads every Matter; a non-member reads no Matter.
- A Matter member reads every note, task, conversation and message in the Matter.
- A restricted document and its version, text, anchors, annotations, relations and chunks are invisible without a grant, except for the firm admin.
- A tool outside the bundle is denied.
- An agent acts as the initiating user; an intern's agent cannot bypass a restricted-document grant.
- A stale approval rejects a commit.
- A prompt injection cannot call a human-only action; approval and deletion stay human.
- A document version is immutable; a changed subject resets approval/readiness.
- A stale document save is refused; a retry does not duplicate a version.
- A review is bound to the submitted version hash; a return leaves the version intact.
- A corpus instrument has source/snapshot/version/reviewer; a stale one is `unconfirmed`.
- A case-law quote/pinpoint verifies deterministically.
- A library item is admin-published and invisible without a grant.
- A workflow run pins its definition; a replay does not duplicate a side effect.
- An agent run has a scope, context package and budget.
- The audit chain verifies; a tampered row fails.
