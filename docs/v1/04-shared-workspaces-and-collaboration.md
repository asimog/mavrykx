# MavrykX — Shared workspaces and collaboration

**Status:** current · **Version:** v1 · **Date:** 2026-11-28

The Matter is the shared workspace. There is no separate Workspace, Project or Space entity. A **section** is a named arrangement of documents inside one Matter; it is not a Workspace and not a permission boundary.

Collaboration is multi-user and sequential. Several lawyers, interns and authorised staff work in one Matter. They see the latest saved state. One user edits a document at a time. There is no real-time co-editing, shared cursor or presence in V1.

---

## 1. The Matter as the shared workspace

The Matter is the unit of confidentiality and the shared record. A document, note, task, assignment, event, conversation, research project or workflow run is scoped to it.

**What is shared:** the Matter spine, the section tree, authorised documents, matter-visible notes, tasks and assignments, events, Matter-wide conversations, submissions, reviews, approvals, decisions, filings, activity and library items granted to the Matter.

**What is private:** a private note, a private conversation, a private task (creator and assignee), a restricted document without a grant, a draft that has not been submitted, a classification proposal before confirmation and an unpublished library item.

**Firm administration is not Matter access.** A firm admin manages users, settings and backups; that role does not by itself open a Matter. A firm admin who is also a Matter member follows that membership. A supervising lawyer is a Matter `lead` or `approver`.

**No second container.** A Workspace/Project would split the confidentiality unit and the record. The Matter already runs from first note to archive. A section is an arrangement row inside the Matter, never a container of authority.

---

## 2. Membership, roles and supervision

Firm roles are `admin`, `lawyer` and `staff`. Matter access is `lead`, `editor`, `viewer` or `approver`. The two combine; neither overrides a wall.

| Matter access | May do |
|---|---|
| `lead` | Manage the Matter, its members and sections; create and edit shared resources; submit; review and approve. |
| `editor` | Create and edit shared resources; submit work; comment. No membership changes and no approval. |
| `viewer` | Read shared resources and comment where the resource allows it. No edit or approval. |
| `approver` | Read shared resources, review submissions and approve or return. No edit of the submitted version. |

An intern is a `staff` or `lawyer` user with `editor` access, not a separate role. A supervising lawyer is a `lead` or `approver`; an admin lawyer who is also the Matter `lead` or `approver` is the supervising lawyer. Approval authority is never inferred from seniority or from the firm `admin` role alone.

The role matrix is one declaration, mirrored by the RLS tests; the client shows the same grants, but the service and RLS decide. Membership changes are audited. Revocation takes effect on the next operation: API session, edit lease, gateway call or RLS check.

---

## 3. The workspace resource model

Every resource carries one `matter_id` and one owning module. A section arranges documents; it does not own or copy them.

| Resource | Owner | Relationship to the Matter | Visibility | Formal review |
|---|---|---|---|---|
| Section (`folder`) | documents | Named, ordered document arrangement; may nest | Matter | No |
| Document | documents | Belongs to one Matter and optionally one section | Matter or restricted | Yes, on a version |
| Document version | documents | Immutable version of one document | Follows the document | Yes |
| Note | matter | Matter-scoped text; its heading is content | Private or Matter; firm-wide notes are not used | No; attach a document version to a submission |
| Task / assignment | work | Matter-scoped work; assignment is its assignee and due date | Private or Matter | Completion; review is via a linked version |
| Appointment | work | Matter-scoped meeting or call; the calendar is derived | Matter | No |
| Deadline | work | Matter-scoped time limit with a basis; the calendar is derived | Matter | No |
| Hearing | proceedings | Dated occurrence in a proceeding; the calendar is derived | Matter | No |
| Conversation / message | harness | Matter-scoped room and attributed turns | Private, shared or Matter | No |
| Research project | research | Matter-scoped plan, sources and findings | Matter | Plan approval; submission via a memo version |
| Approval | approvals | Bound to one subject and hash | Follows the subject | Yes |
| Decision | approvals | Human choice with options and rationale | Matter or restricted | No |

**Relationships.**

- A client may have many Matters; a Matter has zero or one client at intake.
- A document has many immutable versions; one is current.
- A task may link documents through `task_document`; a link never widens document access.
- A section may contain documents from its own Matter only. Moving a document between sections never changes its permissions.
- A conversation has many messages; a message is never edited in place.
- An approval points at one subject hash, normally a document version.
- A research submission is a `research` task plus a submitted document version, an approval and annotations; it is not a new entity.

**No generic file manager.** A document has a type, a version history, a status and, where required, an approval. Uploading a file into a section is not the same as creating a legal record.

---

## 4. Creation, editing, submission and deletion

| Resource | Create | Edit | Submit and review | Delete or archive |
|---|---|---|---|---|
| Section | `lead` or `editor` | Rename, reorder, move; `lead` or `editor` | None | Only when empty of documents and child sections; audited |
| Document | `lead` or `editor` with document edit access | Acquire the edit lease; save a new version | Submit the current version; `lead` or `approver` reviews | Archive; hard delete needs approval and no legal hold |
| Note | `lead` or `editor` | Author, or `lead` for a shared note; every edit audited | None unless attached to a submitted version | Author or `lead`; audited; blocked by a legal hold |
| Task / assignment | `lead` or `editor` | Assignee updates status and comments; only the assignor or `lead` changes the due date | Completion reviewed where the task says so | Cancel; hard delete is exceptional and audited |
| Appointment / deadline / hearing | `lead` or `editor` | Creator or `lead` | None | Cancel or delete; audited |
| Conversation | `lead` or `editor` | Owner changes title and visibility; messages are immutable | None | Owner or `lead` closes or archives |
| Research submission | `lead` or `editor` creates the task and uploads the memo | Assignee edits by new document version | `approver` reviews the submitted version | Archive; the versions survive |
| Approval | Created by submission | No edit; it expires or becomes stale | `lead` or `approver` decides; the author does not decide where another reviewer exists | No delete |

**Rules that apply to every row.**

- Creation records the actor; every later change emits an audit event.
- A new version or revision never overwrites an older one.
- A task assignee holds `editor` or `lead` Matter access; a viewer can be informed but not assigned.
- The assignor or a `lead` owns the due date; an assignee cannot silently extend a deadline.
- A delete is a human act. An agent may propose one; it cannot execute it.
- No hard delete while a legal hold exists.
- A section never becomes a permission boundary.

---

## 5. Access rules

```text
allow = firm membership
        AND matter membership
        AND NOT ethical wall
        AND resource visibility or grant
        AND (for an agent) the initiator's grants ∩ run scope ∩ bundle
        AND (for an edit) the edit lease held by the actor
```

- Matter membership is the outer boundary. A firm admin is not a bypass.
- An ethical wall always denies.
- A `resource_grant` narrows a document, conversation or task inside the Matter; it never widens beyond the Matter and never overrides a wall.
- A restricted document needs a grant; a Matter document is member-readable.
- A private note is owner-only. A private task is creator and assignee. A private conversation is owner-only. Another member, including a `lead` or `approver`, does not read private content by role. The owner shares it or it stays private.
- A shared conversation does not authorise every Matter file. A document link is a reference, not a grant.
- A section does not change access to the documents in it.
- An agent inherits the initiating user, subject to the bundle. It never gains wider access because it is in a shared Matter.
- An agent cannot approve its own work or clear a legal gate.
- Revocation is enforced on the next operation: gateway, RLS, API session, edit lease.
- The service checks it; RLS re-checks it. The UI is not the boundary.
- The visibility rule is declared once and reused by the service and RLS; the API and SQL expressions are bound by the same negative tests.

**Implementation gate.** The baseline `note` policy is Matter-wide; the baseline `task` policy lets a firm admin read a private task; the baseline `agent_run` policy lets a firm admin read a private trace; and the baseline `document_version`, `document_text`, `document_anchor`, `annotation`, `document_relation` and `document_chunk` policies are Matter-wide rather than following a restricted document. Private notes, private tasks and private traces are not exposed until the step 3 policy migration narrows them to the owner (and, for a task, its assignee); restricted-document child rows are not exposed until the step 4 policy migration follows `has_document_access`. No private or restricted resource ships on application checks alone.

---

## 6. Sequential document editing

Euro-Office is the editor. V1 runs the embedded Windows-native editor and `x2t` on the desktop; no `DocService` process, hosted DocumentServer or Docker dependency is part of the collaboration path.

**One editor at a time.**

1. A user opens a document for editing. The service checks document access and acquires an edit lease: one active `editing_session` per document, with the base version, holder and heartbeat.
2. Another authorised user who opens the same document gets the latest committed version read-only. They are not joined to a live session.
3. The holder edits locally and saves through the MavrykX API. The save carries the session id, base version id, base hash and an idempotency key.
4. The service locks the document row, verifies the lease holder and the current base, stores the blob and creates a new immutable `document_version`. The document's current version moves; the audit event records the actor and both hashes.
5. The save releases the lease, or renews it if the editor remains open. A lease expires on a missed heartbeat or is revoked by a `lead`; an expiry or revocation is audited. A user may request takeover of a stuck lease; a `lead` approves it and both the request and the release are audited. Unsaved bytes are a client concern; the server never promotes a live buffer.

**No silent overwrite.** A save against a moved base is refused with `DOC_STALE_BASE`; the editor shows the current version and offers compare or reapply. A save from a lost lease is refused with `DOC_SESSION_REVOKED`. The unique `(document_id, version_no)` constraint and the row lock make the check atomic. A retry with the same idempotency key returns the version already created.

**Version history.** Every save creates a version. Any two versions can be compared read-only. Restoring an old version creates a new version from the old blob; it never rewrites history and it resets approval. There is no server checkpoint and no `editor_recovery` version in V1.

**Agent edits are proposals.** An agent reads a committed version, not a private buffer, and submits a `document_proposal` with base version, base hash, anchor, expected text, patch and run. A human accepts or rejects. Applied proposals create a new version. If the base moved and every anchor's expected text is unchanged, rebase deterministically; if an anchor changed, `needs_human`. Never auto-merge conflicting legal text. An agent cannot apply a proposal while a human holds the edit lease.

**The editor is not the record.** Euro-Office renders and edits; `x2t` converts; the builder is the only agent/offline DOCX mutator; `lxml` reads the OOXML package for verification. The editor gets no database credential, no version-creation path and no permission decision.

**Future real-time collaboration.** The `editing_session` and save contract are the seam. A future co-editing provider could implement the same port; MavrykX would still own versions, permissions and audit. V1 does not implement CRDT, OT, cursors or simultaneous editing, and does not add a second document authority.

---

## 7. Concurrent operations and conflicts

| Situation | Result |
|---|---|
| Two users open the same document for editing | First acquires the lease; second is read-only on the latest version. |
| Second user saves against an old base | `DOC_STALE_BASE`; no version; compare or reapply. |
| Lease expires, another user edits, first user saves | `DOC_SESSION_REVOKED` or `DOC_STALE_BASE`; no overwrite. |
| Two users edit the same note | First revision wins; second gets `RESOURCE_STALE` and reloads. |
| Lead reassigns a task while the assignee updates it | Revision check fails for the stale writer; no silent merge. |
| Supervisor submits a review, then a new version lands | Approval is stale; review the new hash. |
| Agent proposal against a moved base | Stale; rebase only if anchors are unchanged, otherwise `needs_human`. |
| User loses access during an edit lease | Lease revoked; next save or tool call denied. |
| Delete while a document is leased | Delete is refused until the lease closes, or the lead revokes the lease first. |
| Retry of a save or write | Idempotency key returns the prior result; no duplicate version. |

**Decision rule.** Automatic only for read-only work or a deterministic rebase of disjoint anchors. A commit, filing, send, grant, delete or approval is a human act.

---

## 8. Change visibility and attribution

Users read the latest committed state. A saved change is visible to every authorised reader on the next read; no one sees another user's unsaved buffer.

**Delivery.** Matter-scoped SSE on the existing `api` carries an invalidation: resource type, id, revision or version id. It does not carry document content, cursors, typing or presence. Clients refetch the resource. The event stream is transport; `message`, `audit_event` and the saved rows are durable.

**Attribution.** Every write emits an audit event: actor, action, Matter, subject, before/after revision or hash, time and, for an agent, the run and initiating user. Creation columns are a convenience; the audit is the authoritative who/when record. The Activity view reads the audit and the saved rows, not a second history table.

A user can answer, for any shared resource: who created it, who changed it, who submitted it, who reviewed or approved it, who deleted or archived it, and when. A document answer names the version and hash.

**No presence.** There are no cursors, typing indicators, participant lists or live-session banners. The document banner reports the lease holder and the current version, not a live audience.

---

## 9. Tasks, submissions and review

A submission is not a new entity. It is:

- a `task` with an assignee and a due date;
- a `document_version` as the submitted artefact;
- an `approval` bound to the version hash;
- `annotation` rows for comments;
- a notification.

An **assignment** is the task's assignee and due date, not a separate record. A **review** is the human decision on the approval plus its annotations, not a separate table.

**Review states.** The document moves `draft → in_review → approved` or back to `draft`; the task stays `in_progress` until the review is decided. The approval is `pending → approved/rejected/expired/stale`. A new version makes a pending approval stale.

**Review gate.** A review gate raises a task in the Matter; settling the gate settles the task, and completing the task settles the gate. The gate pins the submitted version hash. A later version does not retroactively change the decision; it opens a new review.

**The intern scenario.**

1. The supervising lawyer creates a research task and assigns it to the intern.
2. The intern's agent reads only the intern's authorised sources.
3. The intern uploads the memo and authorities, then submits the current version.
4. The task and document enter review; the approval is bound to the version hash.
5. The supervising lawyer reads that version, comments and approves or returns.
6. A return rejects the approval, reopens the task and leaves the version intact; the intern submits a new version.
7. Approval records the decision; the approved version becomes part of the authorised record. The next edit is a new version.

**Who decides.** A `lead` or `approver` decides. Where the Matter has another eligible reviewer, the author does not approve their own submission. A one-person firm may self-approve; the audit marks it as a self-review.

**Agent boundary.** An agent may draft, propose and prepare a submission; submission, review and approval are human acts. An agent cannot approve its own work, clear a gate or delete a resource. The record names the run and the initiating user.

---

## 10. Shared workflows and research

- A workflow run is Matter-bound. It pins the definition version. A legal gate is a workflow node; the graph cannot clear it.
- A Research Studio project is a Matter-scoped project with a plan, sources, agent runs, findings and review. It is not the Matter chat and not a Pydantic AI Workspace. A firm-scoped project needs a reuse grant.
- A research submission is a `research` task plus a memo version and an approval; it is not a second review system. Every cited source points at a source version, locator and quote; a later version does not silently change the citation.
- A user browser session is Matter-bound. A headless agent session is separate. An agent may operate the user browser only through an explicit, visible, revocable control lease. Captures become documents through the document service.
- A library item is admin-published; access is granted by admin. It is not a Matter file and not primary law.
- A forum adapter syncs cause lists, hearing dates and orders. It is technical; legal requirements remain in corpus/rules.

---

## 11. Distributed execution

The record plane is the firm server. The execution plane is the lawyer's node or another authorised node.

- A run is created with a scope, context package and budget.
- It is leased to one `execution_node`; the node heartbeats.
- If the lease is lost, the run is `suspended`; it is not silently re-run on another node.
- Every tool call goes through the gateway; the node has no database, blob-store or legal authority.
- Every tool effect has an operation id and a status: started, completed, failed, unknown.
- An uncertain effect is surfaced, not assumed. `StepPersistence`/`PostgresStepStore` is the snapshot and effect ledger.
- A revoke stops the next tool call; the run is cancelled or suspended with `RUN_ACCESS_REVOKED`.
- The disposable sha256 cache is derived, never canonical, never a permission.
- Offline is out of scope. Without the API, no new runs and no commits.

**Event delivery.** AG-UI on the node, relay and SSE on the API. The event stream is transport; `message`, `agent_event` and `audit_event` are durable. SSE reconnect replays by sequence. The workspace invalidation feed is separate from the agent stream; neither carries presence.

---

## 12. Sequence — two lawyers and one supervisor

```mermaid
sequenceDiagram
  participant A as Lawyer A
  participant B as Lawyer B
  participant S as Supervisor
  participant API as Document Control
  participant DB as Postgres + blobs

  A->>API: open for edit (base Vn)
  API->>DB: edit lease(Vn, A)
  API-->>A: local editor config
  B->>API: open document
  API-->>B: Vn read-only (A editing)
  A->>API: save(session, Vn, hash, bytes)
  API->>DB: lock; verify; Vn+1; audit
  API-->>A: Vn+1
  B->>API: refresh
  API-->>B: Vn+1
  B->>API: open for edit (base Vn+1)
  API->>DB: edit lease(Vn+1, B)
  A->>API: save stale Vn
  API-->>A: DOC_STALE_BASE (no write)
  B->>API: save(session, Vn+1, bytes)
  API->>DB: Vn+2; audit
  S->>API: review Vn+2
  API->>DB: approval(Vn+2 hash); audit
  API-->>S: approved or returned
```

---

## 13. Collaboration acceptance

- Two users edit one DOCX sequentially: one holds the lease, the other reads the latest saved version; the save creates one immutable version.
- A stale save is refused; no version is created and no text is silently overwritten.
- A lease expires or is revoked; the next editor acquires it; an old save is refused.
- Version comparison is read-only; restoring an old version creates a new version and resets approval.
- A note or task updated against an old revision is refused with `RESOURCE_STALE`.
- A private note and private conversation are invisible to every other Matter member; a private task is invisible except to its assignee; a restricted document is invisible without a grant.
- Cross-Matter access to a document, note, task, event or conversation returns nothing.
- A section move never changes access; deleting a section never deletes a document.
- Every create, edit, submit, review, approve, archive and delete is attributed and audited.
- An intern submits; the supervisor returns and later approves; the original version survives.
- An agent inherits the intern's grants; it cannot read a restricted document or approve its own work.
- A revoked user or node stops at the next tool call, save or callback.
- A retry does not duplicate a version, message or approval.
- No DocumentServer process, hosted editor or Docker dependency is required for collaboration.

**Negative fixtures.** A non-member reading each resource; a walled member; a peer reading a private note, task or conversation; a restricted document without a grant; a revoked grant; a stale note/task revision; a stale document base; a second lease holder; a duplicate save retry; a stale approval; and a cross-Matter link. Each must fail with the named error, not an empty result that looks like success.

---

## 14. Deferred and implementation notes

Live co-editing, shared cursors, presence, simultaneous editing, DocumentServer shared sessions and peer-hosted editor services are deferred and are not part of V1. The previous shared-session design is superseded for the CRM build order; the editing-session and save seam is retained so a future decision can add co-editing without a second document authority.

Editor packaging, the local Euro-Office tree, `x2t`, lease heartbeat and expiry defaults, browser control details, Research Studio scope and trace retention are recorded in `docs/implementation/eurooffice-integration-plan.md` and the owning module; they do not reopen the architecture. Application-service contracts are in [03-application-agent-and-data.md](03-application-agent-and-data.md); the resource model is in [02-domain-model.md](02-domain-model.md).
