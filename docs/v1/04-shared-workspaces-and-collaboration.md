# MavrykX — Shared workspaces and collaboration

**Status:** current · **Version:** v1 · **Date:** 2026-11-26

The Matter is the shared workspace. There is no separate Workspace, Project or Space entity. Lawyers, staff and their agents work inside one Matter, with private and shared surfaces.

---

## 1. The Matter as the workspace

The Matter is the unit of confidentiality and the shared record. A conversation, document, task, run, research project or workflow run is scoped to it.

**What is shared:** the Matter spine, authorised files, Matter-wide conversations, matter-visible tasks, approvals, decisions, filings, activity and the library items granted to the Matter.

**What is private:** a lawyer’s private conversation, a private task, a restricted document without a grant, a private run trace, a classification proposal before confirmation, and an unpublished library item.

**No second container.** A Workspace/Project would split the confidentiality unit and the record. The Matter already runs from first note to archive.

---

## 2. Conversations

A conversation belongs to one Matter. `visibility` is:

- **private** — the owner and the owner’s runs;
- **shared** — the owner plus explicit `resource_grant` participants at `view` or `post`;
- **matter** — every Matter member may read and post, subject to walls.

Every turn is an attributed `message` row. A message is execution state, never a legal record. An answer worth keeping is saved as a note, research row or memo.

**Attribution.** A user message carries the author. An agent message carries the run and the launching user, displayed as “Maverick for <name>”. A shared conversation does not merge identities.

**Agent scope.** A run is bound to the launching user’s grants, never the union of participants and never the conversation’s audience. An intern launching Maverick in the shared room gets an intern’s run.

**Private traces.** A private conversation’s `agent_run`, `agent_event` and `context_package` are readable by the launching user and an admin, not by every Matter member. A shared/matter conversation’s trace follows its readers.

**Delivery.** Matter-scoped SSE on the existing `api`: messages, presence, typing. No broker. Presence is ephemeral, never a table.

---

## 3. Access rules

- Matter membership is the outer boundary.
- An ethical wall always denies.
- A `resource_grant` narrows a document, conversation or task inside the Matter; it never widens beyond the Matter.
- A restricted document needs a grant; a matter document is member-readable.
- A private task is visible to creator, assignee and admin; a matter task to members.
- A shared conversation does not authorise every Matter file. A document link is a reference, not a grant.
- An agent inherits the launching user, subject to the bundle. It never gains wider access because it is in a shared Matter.
- An agent cannot approve its own work.
- Revocation is enforced on the next operation: gateway, RLS, session/lease, DocumentServer `drop`.

**Enforcement shape:**

```text
allow = firm role
        AND matter membership
        AND NOT wall
        AND resource grant (where the resource is narrowed)
        AND (for an agent) run scope ∩ bundle
```

The service checks it; RLS re-checks it. The UI is not the boundary.

---

## 4. Live document editing

Human–human co-editing uses the Euro-Office DocumentServer in a shared session, hosted by the firm server or the sharing client. The editor owns the live session and pixels; MavrykX owns identity, versions, permissions, approvals and audit.

- The session opens from a committed base version. `editing_session.id` is the Docs API key.
- One active session per document.
- The session save creates an immutable `document_version`.
- A checkpoint is derived; a crash can promote the last checkpoint to an unapproved `editor_recovery` version.
- The session fences out-of-session commits (`DOC_SESSION_ACTIVE`).
- Presence, cursors and typing are editor state; not records.
- A callback carries the session id and a service-signed token; the Document Control Service verifies it.

**Docs API is the live path.** WOPI is a file-access/locking fallback. WOPI mode loses plugins, JWT server restriction, toolbar control and paragraph-locking; a WOPI lock is file-level and does not coordinate a live session. Do not use WOPI `PutFile` as an out-of-session write into a live document.

**Agent edits are proposals.** An agent reads a committed version, not the live buffer, and submits a `document_proposal` with base version, base hash, anchor, expected text, patch and run. The reviewer accepts or rejects. Applied proposals create a new version; the proposal is working state, not the version.

**Rebase.** If the base moved and every anchor’s expected text is unchanged, rebase deterministically. If an anchor changed, `needs_human`. Never auto-merge conflicting legal text.

**Why not CRDT/OT in MavrykX.** The editor supplies human–human collaboration. A second CRDT/OT layer would duplicate it, lose native track changes and comments, and create a second document authority.

**Direct live agent editing** is not proven. It needs a supported plugin/Automation API with tracked-change, authorship, conflict and revocation tests. It is not assumed.

**Recovery.** A DocumentServer crash loses unsaved live edits since the last checkpoint. The last checkpoint can be recovered as an unapproved version; the loss window is measured and audited. The legal record is the last committed version.

---

## 5. Concurrent editing outcomes

| Situation | Result |
|---|---|
| Two humans edit the same paragraph | Editor orders the changes; both survive. |
| Two agents edit the same paragraph | First proposal commits; second is stale; if its anchor changed, `needs_human`. |
| Two agents edit different paragraphs | Second rebases onto the new base if its anchors are unchanged. |
| Lawyer edits while agent proposes | Proposal base is older; stale; current text returned; re-propose or rebase. |
| Lawyer has unsaved changes when agent submits | Session fence refuses the agent commit; proposal stored. |
| Agent submits against a stale version | `DOC_STALE_BASE`; no write. |
| Document saved while another session is active | Second opener joins the same session; a different session key is refused. |
| User loses access during a session | `drop`; next callback/tool call denied; session revoked. |
| Agent retries the same change | Proposal idempotency key + applied version id; return the prior result. |

**Decision rule:** automatic only for read-only work or a deterministic rebase of disjoint anchors. Tracked changes get batch review. Commit, filing, send, grant and delete are human gates.

---

## 6. Distributed execution

The record plane is the firm server. The execution plane is the lawyer’s node or another authorised node.

- A run is created with a scope, context package and budget.
- It is leased to one `execution_node`; the node heartbeats.
- If the lease is lost, the run is `suspended`; it is not silently re-run on another node.
- Every tool call goes through the gateway; the node has no database, blob-store or legal authority.
- Every tool effect has an operation id and a status: started, completed, failed, unknown.
- An uncertain effect is surfaced, not assumed. `StepPersistence`/`PostgresStepStore` is the snapshot and effect ledger.
- A revoke stops the next tool call; the run is cancelled/suspended with `RUN_ACCESS_REVOKED`.
- The disposable sha256 cache is derived, never canonical, never a permission.
- Offline is out of scope. Without the API, no new runs and no commits.

**Event delivery.** AG-UI on the node, relay and SSE on the API. The event stream is transport; `message`, `agent_event` and `audit_event` are durable. SSE reconnect replays by sequence. Presence is ephemeral.

---

## 7. Tasks, submissions and review

A submission is not a new entity. It is:

- a `task` with an assignee;
- a `document_version` as the submitted artefact;
- an `approval` bound to the version hash;
- `annotation` rows for comments;
- a notification.

A review is the human decision on the approval plus its annotations. A request for changes is a rejected/returned approval and a new version. Acceptance never overwrites; the next edit is a new version.

The intern scenario:

1. Partner creates a research task.
2. Intern’s agent reads only the intern’s authorised sources.
3. Intern uploads the memo and authorities.
4. Intern submits with an approval bound to the version hash.
5. Partner reviews and comments.
6. Partner approves or returns; the original survives.
7. Approved work becomes part of the authorised record.

---

## 8. Shared workflows and research

- A workflow run is Matter-bound. It pins the definition version. A legal gate is a workflow node; the graph cannot clear it.
- A Research Studio project is a workspace with a plan, sources, agent runs, findings and review. It is not the Matter chat. It is Matter-scoped by default; a firm-scoped project needs a reuse grant.
- A user browser session is Matter-bound. A headless agent session is separate. An agent may operate the user browser only through an explicit, visible, revocable control lease. Captures become documents through the document service.
- A library item is admin-published; access is granted by admin. It is not a Matter file and not primary law.
- A forum adapter syncs cause lists, hearing dates and orders. It is technical; legal requirements remain in corpus/rules.

---

## 9. Sequence — two lawyers and one agent

```mermaid
sequenceDiagram
  participant A as Lawyer A
  participant B as Lawyer B
  participant DS as Euro-Office
  participant API as Document Control
  participant M as Maverick (A's run)
  participant DB as Postgres + blobs

  A->>API: open document (base Vn)
  API->>DB: editing_session(base Vn)
  API-->>A: signed Docs API config
  A->>DS: join live session
  B->>API: open same document
  API->>DB: join active session
  API-->>B: same session key
  B->>DS: join live session
  A->>DS: edit paragraph 12; comment
  B->>DS: edit paragraph 40; reply
  M->>API: doc_open(document, Vn)
  M->>API: document.propose(anchor 12, expected, patch)
  API->>DB: proposal(base Vn, hash)
  A->>DS: closes editor
  DS->>API: final save callback
  API->>DS: download saved DOCX
  API->>DB: Vn+1; proposal stale
  API->>API: anchor 12 changed → needs_human
  A->>API: review proposal; accept/reject
  API->>DB: Vn+2 or rejection; audit
```

---

## 10. Collaboration acceptance

- Two users edit one DOCX in one session; both see changes, comments and track changes; authors correct; one immutable version.
- An agent proposal against a stale base is detected; it never overwrites the session.
- A private conversation and its trace are invisible to another Matter member.
- A restricted document is invisible without a grant, including in retrieval.
- A shared conversation does not widen document access.
- A revoked user or node stops at the next tool call/callback.
- A retry does not duplicate a commit.
- A DocumentServer crash is recoverable from the last checkpoint; the loss window is recorded.
- A user browser and agent browser are separate; a handoff is visible and revocable.
- Every human and agent action is attributable.

---

Editor plugin scope, DocumentServer packaging, checkpoint frequency, browser control details, Research Studio scope and trace retention are recorded in `docs/implementation/eurooffice-integration-plan.md` and the owning module; they do not reopen the architecture.
