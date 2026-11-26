# MavrykX — Product experience

**Status:** current · **Version:** v1 · **Date:** 2026-11-26

The lawyer’s work is the interface. MavrykX is not a chat app with a document tab. It is a workspace where the Matter, its record and the next step are visible, and the agent is a controlled participant.

Three rules:

1. **Work first, chat second.** The home screen is today’s work, not a conversation.
2. **One inbox.** Proposed facts, document changes, citation failures, format defects, classification questions and approvals arrive in one review queue.
3. **The agent is visible.** Every run shows its scope, what it read, what it proposes and what it needs. No hidden autonomy.

---

## 1. Navigation

**Global rail:** Today · Matters · Documents · Research Studio · Library · Workflows · Calendar · Review · Agent activity · Settings.

**Matter workspace:** Overview · Work · Documents · Evidence & Facts · Research & Authorities · Proceedings & Hearings · Filings · Activity.

**Contextual:** Matter setup (classification) · Maverick dock · browser · document right panel.

**What belongs where:**

- Global: the lawyer’s queue across Matters, search, settings.
- Matter: everything true only within the engagement.
- Contextual: the agent, browser and document tools, because they act on the current record.

No separate dashboard page. Today is a work queue, not a chart.

---

## 2. Today

A single queue of what needs the lawyer:

- hearings this week;
- deadlines, with the basis visible;
- approvals waiting;
- review items assigned;
- tasks due;
- Matters with no next step;
- classification questions that block a proceeding;
- library/workflow items awaiting admin publication.

Each row links to the Matter or item. No vanity metrics.

---

## 3. Matter workspace

The Matter spine is always visible: client, parties, proceedings, current step, next date.

- **Overview** — client, scope, key dates, open gates, current work, recent activity.
- **Work** — tasks, deadlines, decisions, workflow runs.
- **Documents** — the Matter’s folder tree; versions, status, filing sets; live-editing indicator and presence.
- **Evidence & Facts** — fact matrix, evidence register, chronology, links.
- **Research & Authorities** — queries, results, corpus/case-law status, citation status.
- **Proceedings & Hearings** — proceedings, application tree, hearings, orders, next dates, forum adapter status.
- **Filings** — filing sets, acknowledgments, defects, responses.
- **Activity** — human decisions, approvals, agent runs, audit events.

The Overview is `matter_now`: current step, next hearing, next deadline with basis, open approvals, unconfirmed facts, stale extractions. Rebuilt from the record; never a second source of truth.

---

## 4. Matter setup and classification

Matter creation is short: title or short description, client/instructing party if known, a folder/document/case number if available, and new versus existing proceeding. A Matter may be one note.

After the Matter exists, **Matter setup** proposes classification. It is guided, not a form.

- It shows what is known, inferred, missing, conflicting or not assessed.
- Each field has evidence, status and a question if useful.
- It asks one useful question at a time.
- The advocate confirms or corrects.
- A Proceeding is created only from confirmed classification.
- A later document can trigger a review proposal.
- A confirmed field is not silently overwritten.

The panel shows what blocks what. A missing filing date does not block evidence review; a missing impugned judgment may block an SLP workflow.

---

## 5. Document view

- The DOCX/PDF in the editor or a rendered proof.
- Right panel: sources, citations, checks, versions, comments.
- Live-session banner: participants, presence, cursors; one active session per document. Saving is the session’s commit; an out-of-session commit is visibly refused.
- Agent proposals appear as tracked changes or a diff against a named base version. A stale proposal shows the current text and the conflict; same-anchor conflict asks for a human.
- The approval card shows the exact version hash and the checks that passed, failed or were waived.
- A restricted document shows a lock and who may open it; it is not a prompt source unless the reader may read it.

---

## 6. Browser, Research Studio, Library, Workflows

- **Browser.** A user tab is Matter-bound. A separate headless agent session runs behind it. An agent handoff to the user browser is explicit: visible banner, control lease, stop control, audit event.
- **Research Studio.** A project workspace with a plan, sources, agent runs, findings and review. It is not the Matter chat. A Matter may have zero or many projects.
- **Library.** Firm templates, precedents, checklists and know-how. Admin publishes; admin grants access. A template is read-only to drafting until a new version is published.
- **Workflows.** A Pydantic Graph creator: typed nodes, edges, gates and budgets. A playbook is a workflow kind. The creator validates the graph; it does not run arbitrary code.
- **Forum adapters.** Settings show the adapter, source, last sync, health and technical-only status. A cause-list import is a reviewed proposal; an order download becomes a document.

---

## 7. The Maverick dock

A dock, not a separate app. Available on every Matter screen.

- **Scope banner** — Matter, conversation visibility, bundles, model, budget, permissions, node.
- **Composer** — ask, instruct, attach a document/source.
- **Run timeline** — thinking states in the lawyer’s language; expandable to tool calls and sources.
- **Approval cards** — exact operation, subject, hash, diff, cost.
- **Waiting state** — what the run needs: a decision, a document, a client answer, a date.
- **Stop/pause** — cooperative cancellation; partial result preserved.

**What the lawyer never sees:** raw chain-of-thought, internal agent topology, raw tool names without a plain-language label, or a model’s self-assessment as proof.

The dock consumes the AG-UI stream from the server via `@ag-ui/client`. Interrupts render as approval cards; custom events as the timeline and waiting states; tool events as expandable steps. Hosted Intelligence is excluded; no Node runtime in the firm install.

---

## 8. Review inbox

One queue:

- proposed fact;
- stale extraction;
- document change (agent edit);
- citation failure;
- format defect;
- completion defect;
- classification question/conflict;
- approval request (commit, filing, send, grant, delete).

A waiver is explicit: it names the failed check, actor, reason and time. It never turns a failure into a pass. Approval latency is measured; a queue that trains lawyers to approve without reading is a product defect.

---

## 9. Settings and access

- **Firm** — name, defaults, retention, model policy.
- **Members** — invite as lawyer or staff; role, disable, sessions/devices; first member is admin.
- **Matter access** — grants, walls, resource grants for restricted documents, shared conversations and private tasks.
- **Library** — admin publication, versions, access grants.
- **Workflows** — Pydantic Graph definitions, versions, budgets, publication.
- **Corpus and case law** — sources, snapshots, reviewers, freshness, conflicts.
- **Forum adapters** — technical adapters, source allowlist, sync health, last import.
- **Rules and templates** — published versions, sources, verifiers.
- **Integrations** — email, calendar, research provider, storage.
- **Backups** — last backup, verify, restore drill.
- **Audit** — verify chain, export.

Access changes are gated and audited. A wall is not a setting a user can remove.

---

## 10. Onboarding

One firm per installation; a setup token; the first lawyer becomes admin.

1. Enter the setup token; create the admin account.
2. Set retention and model policy.
3. Solo: open the first Matter with a note. Firm: invite lawyers and staff.
4. Create the first client when there is one; open the Matter properly. Notes alone were enough.
5. Import the first documents into the Matter folders.
6. Run the first workflow, or ask Maverick with the Matter’s documents in scope.

No product tour, no empty dashboard. The first screen is a Matter with a next step — even if the whole Matter is one note.

---

## 11. What not to build

- A dashboard of charts with no action.
- A separate “AI chat” product disconnected from the Matter.
- A settings page that exposes model parameters to a lawyer.
- A notification stream that duplicates the review inbox.
- A calendar that owns dates instead of projecting them.
- A document editor that silently becomes the record.
- A second editor engine for agent edits.
- A private conversation or private trace shown to every Matter member.
- A live-session save that silently overwrites another writer’s version.
- A Matter creation form that asks every legal and procedural detail.

---

## 12. Accessibility and clarity

- Keyboard-first for the review inbox and approval cards.
- Plain-language labels; a tool call is described by what it did, not its internal name.
- Every check states its rule, its source and its date.
- Every number (deadline, amount, date) links to its basis.
- Dark mode is a theme, not a separate design.
