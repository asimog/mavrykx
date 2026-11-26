# Maverick — UI and product experience

**Status:** current · **Date:** 2026-11-26

---

## 1. The principle

The lawyer's work is the interface. The product is not a chat app with a document tab; it is a workspace where the matter, its record and its next step are visible, and the agent is a controllable participant.

Three rules:

1. **Work first, chat second.** The home screen is today's work, not a conversation.
2. **One inbox.** Proposed facts, document changes, citation failures, format defects and approvals arrive in one review queue.
3. **The agent is visible.** Every run shows its scope, what it read, what it proposes and what it needs. No hidden autonomy.

---

## 2. Navigation

| Level | Items |
|---|---|
| **Global rail** | Today · Matters · Documents · Research · Calendar · Review · Agent activity · Settings |
| **Matter workspace** | Overview · Work · Documents · Evidence & Facts · Research & Authorities · Proceedings & Hearings · Filings · Activity |
| **Contextual** | Maverick dock (chat + run timeline), document right panel (sources, citations, checks, versions) |

**What belongs where.**

- **Global:** the lawyer's queue across matters, search, settings.
- **Matter:** everything that is true only within the engagement.
- **Contextual:** the agent and the document tools, because they act on the current record.

No separate "dashboard" page. Today is a work queue, not a chart.

---

## 3. The three screens that matter

### 3.1 Today

A single queue of what needs the lawyer:

- hearings this week;
- deadlines, with the basis visible;
- approvals waiting;
- review items assigned;
- tasks due;
- matters with no next step.

Each row links to the matter or the item. No vanity metrics.

### 3.2 Matter workspace

The matter spine is always visible: client, parties, proceedings, current step, next date.

| Tab | Contents |
|---|---|
| **Overview** | Client, scope, key dates, open gates, current work, recent activity |
| **Work** | Tasks, deadlines, decisions, playbook runs |
| **Documents** | The matter's own folder tree — default folders seeded by document type, arranged and movable; versions, status, filing sets inside |
| **Evidence & Facts** | Fact matrix, evidence register, chronology, links |
| **Research & Authorities** | Queries, results, authorities, citation status |
| **Proceedings & Hearings** | Proceedings, the application tree, hearings, orders, next dates |
| **Filings** | Filing sets, acknowledgments, defects, responses |
| **Activity** | Human decisions, approvals, agent runs, audit events |

The Overview is the **`matter_now`** read model: current step, next hearing, next deadline with its basis, open approvals, unconfirmed facts and stale extractions — rebuilt from the record, never a second source of truth.

### 3.3 Document view

- The document (DOCX/PDF) in the editor or a rendered proof.
- A right panel with **sources**, **citations**, **checks**, **versions**, **comments**.
- The agent's proposed changes are visible as tracked changes or a diff; nothing is silent.
- The approval card shows the exact version hash and the checks that passed, failed or were waived.

---

## 4. The Maverick dock

A dock, not a separate app. It is available on every matter screen.

| Element | Purpose |
|---|---|
| **Scope banner** | Matter, bundles, model, budget, permissions — and the node the run executes on |
| **Composer** | Ask, instruct, or attach a document/source |
| **Run timeline** | Thinking states in the lawyer's language; expandable to tool calls and sources |
| **Approval cards** | The exact operation, subject, hash, diff, cost |
| **Waiting state** | What the run needs: a decision, a document, a client answer, a date |
| **Stop / pause** | Cooperative cancellation; partial result preserved |

**What the lawyer never sees:** raw chain-of-thought, internal agent topology, tool names without a plain-language label, or a model's self-assessment as proof.

**Plumbing (RD-40/41).** The dock consumes the AG-UI event stream from the server — `@ag-ui/client` in the renderer. Interrupts render as approval cards; custom events render as the plain-language timeline and waiting states; tool events render as expandable steps. Hosted Intelligence is barred by FD-7, a Node runtime is barred by the packaging budget, and the prebuilt chat surface breaks the rules above anyway.

---

## 5. Review inbox

One queue, seven kinds of item:

| Item | Source | Action |
|---|---|---|
| Proposed fact | Extraction | Accept, edit, reject with reason |
| Stale extraction | Text re-run or re-OCR (RD-61) | Re-review against the current text; the old proposal never shows as current |
| Document change | Agent edit | Review tracked changes as a batch; accept, reject, comment |
| Citation failure | Verification | Fix, replace, waive with reason |
| Format defect | Rule check | Fix, waive with reason |
| Completion defect | Completion contract (RD-62) | Add the missing section or field |
| Approval request | Commit/filing/send/grant/delete | Approve, reject, ask for changes |

A waiver is explicit: it names the failed check, the actor, the reason and the time. It never turns a failure into a pass. Approval latency is measured: a queue that trains lawyers to approve without reading is a product defect (RK-20).

---

## 6. Settings and access

| Area | Contents |
|---|---|
| Firm | Name, defaults, retention, model policy |
| Members | Invite as `lawyer` or `staff`, role, disable, session/device list; the first member is the admin |
| Matter access | Grants and walls, per matter |
| Rules and templates | Published versions, sources, verifiers |
| Integrations | Email, calendar, research provider, storage |
| Backups | Last backup, verify, restore drill |
| Audit | Verify chain, export |

Access changes are gated and audited. A wall is not a setting a user can remove.

---

## 7. Onboarding

One firm per installation; a setup token; the first lawyer becomes the admin (FD-11).

1. First run: enter the setup token, create the admin account. The firm exists; one lawyer can be the firm.
2. Set retention and the model policy.
3. Solo: open the first matter with a note. Firm: invite the first lawyers and staff.
4. Create the first client when there is one; open the matter properly — notes alone were enough to start.
5. Import the first documents into the matter's folders.
6. Run the first reference playbook, or simply ask Maverick with the matter's documents in scope.

No product tour, no empty dashboard. The first screen is a matter with a next step — even if the whole matter is one note.

---

## 8. What not to build

- A dashboard of charts with no action.
- A separate "AI chat" product disconnected from the matter.
- A settings page that exposes model parameters to a lawyer.
- A notification stream that duplicates the review inbox.
- A calendar that owns dates instead of projecting them.
- A document editor that silently becomes the record.

---

## 9. Accessibility and clarity

- Keyboard-first for the review inbox and approval cards.
- Plain-language labels; a tool call is described by what it did, not its internal name.
- Every check states its rule, its source and its date.
- Every number (deadline, amount, date) links to its basis.
- Dark mode is a theme, not a separate design.

---

*Back to [00-README.md](00-README.md).*
