# MavrykX — Detailed architecture

**Status:** current · **Version:** v1 · **Date:** 2026-11-28

MavrykX is a self-hosted legal-work platform. **Maverick** is its one agent. The Matter is the workspace; there is no separate Workspace or Project entity.

The product is built in two stages: the legal CRM and shared Matter workspace first, Maverick's AI Legal Harness second. The CRM is a complete multi-user product before the agent is wired in.

The platform is a modular monolith with a firm server, Electron clients and authorised execution nodes. It is **not** a CRUD legal app with a chatbot, and it is **not** a multi-tenant SaaS.

---

## 1. What is fixed

- Electron desktop; React renderer; Python server.
- Pydantic for contracts; Pydantic AI for the agent; the Pydantic AI Harness for agent machinery.
- PostgreSQL as the authoritative database; content-addressed blobs for bytes.
- One agent, Maverick. Sub-agents are tools of that agent, not peer agents.
- CRM foundations first; the AI legal harness second.
- One firm with multiple users; a client may have many Matters.
- One shared Matter workspace; sequential document editing. No real-time co-editing in V1.
- Self-hosted per firm; one installation serves one firm.
- Human approval for commit, filing, send, grant and delete.
- DOCX/PDF is the work product; chat is not a legal record.
- Matters may start with a note alone; a client is optional at intake.
- Indian forums only.
- One application-service layer; CLI, HTTP and agent tools call it.
- No conflict-check subsystem; the matter-open gate records client and scope.

---

## 2. Deployment shapes

Installed and running are different facts. Every client installs the local editor; the server pack is installed but is not started in V1.

- **Local.** One local Python process runs `api` + `worker`. Bundled PostgreSQL. Electron on the same machine. The Euro-Office frontend and `x2t` are installed; no `DocService` process runs.
- **Firm LAN.** Firm server runs the Python roles. PostgreSQL and blobs live on the firm server. Electron on each desk; document editing is local and saves through the API.
- **Firm remote.** Same firm server behind the remote connection service. No legal data at the relay.
- **Shared live session — deferred.** For a future live co-editing decision, the server pack could run `DocService`, `FileConverter` and the PostgreSQL queue on the firm server or a sharing client on the LAN. That is not a hosted DocumentServer service. It is not part of V1, not started by the CRM, and not required for multi-user collaboration.

The default installer is the shared-capable app: under 15 minutes and under 3.5 GB installed. A local-only build without the server pack stays under 1.5 GB. Redis is not used; the queue is PostgreSQL. Editor session stores are editor-session infrastructure, never legal stores. V1 has no Docker dependency.

---

## 3. Runtime planes

```mermaid
flowchart TB
  subgraph Clients["Desktops — execution nodes"]
    UI["React workspace"]
    ED["Euro-Office editor"]
    AG["Maverick run<br/>agent loop + AgentComposition"]
    BD["Builder + x2t"]
    CACHE["Disposable sha256 cache"]
  end

  subgraph Server["Firm server — MavrykX record plane"]
    API["FastAPI<br/>sessions, services, AG-UI relay"]
    GW["ToolGateway"]
    DOC["Document Control"]
    APPR["Approvals, gates, decisions"]
    AUD["Legal audit"]
    WK["Worker<br/>OCR, ingest, portals, jobs"]
    Q["Postgres job queue<br/>leases, heartbeats"]
  end

  subgraph Data["Firm-controlled records"]
    PG[("PostgreSQL + RLS")]
    BL[("Blob store")]
  end

  UI --> API
  ED -->|"local edit; save bytes"| API
  AG -->|"tool calls"| API
  AG --> BD
  BD --> DOC
  CACHE --> AG
  API --> GW
  GW --> DOC
  GW --> APPR
  GW --> AUD
  API --> PG
  DOC --> PG
  DOC --> BL
  WK --> GW
  Q --> WK
  API -->|"SSE / AG-UI"| UI
```

- **Record plane:** PostgreSQL with RLS, blobs, application services, one gateway, approvals and audit.
- **Editing plane:** the Windows-native Euro-Office editor on the desktop, `x2t` for conversion and the builder for agent/offline DOCX work. MavrykX owns identity, versions, permissions, approvals and audit. No DocumentServer process is part of V1.
- **Execution plane:** stateless Maverick runs on a node. Every tool call crosses the authenticated API session to the gateway. The node has no local authority.

**The editor is not the record.** It gets no database credential and no version-creation path. It opens a committed base under an edit lease and returns saved bytes to the API; only the holder of the lease may save, and only against that base.

---

## 4. Modules

### Matter management — the Clio-shaped substrate

- `identity` — firm, user, membership, session, device, execution node.
- `access` — matter membership, ethical wall, reuse grant, resource grant, the one visibility policy.
- `contacts` — contact, client.
- `matter` — matter, parties, relations, notes.
- `work` — tasks, assignments, task-document links, deadlines, appointments.
- `documents` — sections/folders, document identity, versions, anchors, annotations, edit leases, proposals, compare and restore.
- `storage` — content-addressed blobs.
- `notifications` — notification and delivery state.

This layer works with notes alone. It does not classify, research, draft or run agents. Steps 1–6 of the build order deliver this layer; the agent modules are wired in step 7.

### Litigation and forums

- `courts` — forum directory and hierarchy.
- `forum_adapters` — cause lists, hearing dates, order downloads, case status. Technical only; not a legal rule engine.
- `proceedings` - proceeding, proceeding application tree, proceeding detail/classification, hearings, orders, registry events.
- `filing` — filing, filing items, fees, acknowledgment, response. Portal attempts and confirmation are deferred.

### Legal intelligence

- `classification` — guided matter intelligence after the Matter is opened; the advocate confirms or corrects.
- `corpus` — primary-law ingestion only: court rules, statutes, laws, regulations, notifications.
- `case_law` — judgments, authorities, citations and treatment.
- `rules` — operational format/procedural rules derived from corpus provisions.
- `research` — research queries and results.
- `research_studio` — multi-agent research projects and plans.
- `library` — firm templates, precedents, checklists and know-how; admin publishes, admin grants.
- `facts` — facts, evidence, positions, statuses, exhibits, evidence notebook.
- `analysis` — issues, arguments and argument authorities.
- `drafting` — render jobs; reads library templates. Owns no table.
- `verification` — citation, quote, pinpoint, format, cross-reference and completion checks.
- `approvals` — approval, gate, decision and the review queue read model.

### Agent and automation

- `capabilities` — bundle, bundle version, skill.
- `workflow` — Pydantic Graph definitions, versions, runs, steps and jobs. A playbook is a kind.
- `harness` — conversations and messages from step 5; runs, events, context packages and run-bundle provenance from step 7.
- `browser` — user browser and separate headless agent browser; explicit control handoff.
- `policy` — egress and capability policy.
- `audit` — legal audit chain.

### Interfaces

- `api` — FastAPI, sessions, SSE/AG-UI relay.
- `gateway` — one `ToolGateway`.
- `worker` — OCR, ingest, portal jobs, scheduled work.
- `cli` — Typer over application services.
- `desktop` — Electron main, preload, renderer.
- `agent` — Pydantic AI loop inside a run.
- `composition` — `AgentComposition`, the only wiring root.

---

## 5. Tech stack

Versions checked on 2026-11-26. Pin exact versions.

### Backend

- Python **3.14.10** target; Pydantic AI floor **3.11**. 3.14 is chosen for the Harness wheel and dependency set; 3.15 is not targeted.
- Pydantic **2.14.4**.
- pydantic-settings **2.16.3** for typed configuration.
- Pydantic AI Harness **0.75.0**, pinned exactly. It requires `pydantic-ai-slim` **2.75.0**; `pydantic-ai` and `pydantic-graph` are not pinned separately. Provider extras are added to `pydantic-ai-slim`.
- FastAPI **0.165.0**.
- SQLAlchemy **2.1.9**; asyncpg **0.32.0**; Alembic **1.20.1**.
- Typer **0.29.3**.
- ag-ui-protocol **1.0.0**.
- `lxml` **6.1.3** reads OOXML for verification; `python-docx` **1.2.0** is optional for simple extraction; `pypdf` **7.2.0** extracts PDF text; the builder is the only writer.
- OCR is local: `ocrmypdf` **17.14.2** for PDFs, `pytesseract` **0.3.13** for images, Tesseract 5.x with English and Indic language data pinned with the installer.
- `argon2-cffi` **25.1.0** for passwords; `pyotp` **2.12.1** for TOTP; `aiosmtplib` **5.1.3** and `imap-tools` **1.16.0** for email, deferred.
- OpenTelemetry **1.45.2**; structlog **26.1.0**; `logfire` **6.0.1** optional and development-only.
- pytest **9.2.0**; pytest-asyncio **1.5.0**; hypothesis **6.170.17**; pytest-cov **7.1.0**; httpx **0.29.0**.
- ruff **0.17.6** (including the `S` security rules); mypy **2.4.1**; import-linter **2.17**; pip-audit **2.10.1**; uv **0.13.10**; `just` pinned in CI.
- `python-multipart` **0.0.34** for uploads; `itsdangerous` **2.2.0** for signed URLs; `cryptography` **50.0.2** for device keys.
- DBOS **3.7.0** optional behind `ExecutionEngine`.
- Alembic is the migration runner; revisions are numbered and forward-only, and `downgrade` is not implemented. The baseline revision executes `0001_core.sql`. `alembic check` fails CI on drift between the models and the migrations.

### Data

- PostgreSQL **17.12** is the V1 baseline. PostgreSQL 19 is not targeted.
- pgvector **0.8.7**; Python client **0.5.1**.
- Blob store on the firm's disk/storage.

### Desktop

- React / React DOM **19.3.1**.
- TanStack Router **1.170.46**; TanStack Query **5.108.4**.
- Electron **45.5.0** (Chromium **156.0.8078.109**, Node **24.22.3**). The bundled Node is the native-module ABI; the build Node is not.
- Vite **8.4.0**; TypeScript **6.0.3**, not 7.0.2: `typescript-eslint` 8.74 supports `<6.1.0`; pin 6.0.3 until the lint toolchain supports 7.
- Tailwind CSS **4.3.5**; `@vitejs/plugin-react` **6.3.0**.
- `@ag-ui/client` **1.0.5**.
- Zustand **5.1.0** for UI and session state; TanStack Query owns server state.
- `openapi-typescript` **7.13.0** and `openapi-fetch` **0.17.0** generate and call the API client.
- `ajv` **8.20.0** validates generated JSON Schema in the renderer; `react-hook-form` **7.92.0** handles forms.
- `@tailwindcss/vite` **4.3.5**; `eslint` **10.15.0**; `typescript-eslint` **8.74.0**; `eslint-plugin-import-x` **4.18.1**; `vitest` **5.1.2**; `@testing-library/react` **16.3.3**; `@playwright/test` **1.65.1**; `electron-builder` **26.18.0**; `dependency-cruiser` **18.9.0**.
- `electron-vite` **6.0.0**; `@tanstack/router-plugin` **1.169.0**; `@types/node` **24.19.4** (matches Electron's Node 24.22.3); `@types/react` **19.3.3**; `@types/react-dom` **19.3.0**.
- Node **26.13.1** development/build only.

### Editor

- Euro-Office **9.3.8** DesktopEditors for the V1 local editor. The DocumentServer build stays pinned and installed in the server pack, but no `DocService` process runs and no hosted DocumentServer or Docker dependency is introduced.
- The integration is the embedded editor plus `x2t`; saves go through the MavrykX API. Docs API/WOPI shared-session integration is deferred with live co-editing.
- The local profile uses the vendored editor and builder; the server pack is installed but not started by the CRM.

---

## 6. Layers and dependency rules

### Layers

1. **Domain** — entities, value objects, invariants and policies. Pure Python. No FastAPI, SQLAlchemy, Pydantic AI, Electron, filesystem or network.
2. **Application services** — use cases, transactions, authorisation, audit. Depends on domain and ports.
3. **Infrastructure** — PostgreSQL repositories, blob store, browser, Euro-Office, model providers, court adapters. No business authority.
4. **Interfaces** — FastAPI, Typer, Pydantic AI tools, Electron IPC/renderer. Thin.
5. **Agent composition** — `AgentComposition` and legal pack. Wires Harness capabilities and tools to services through the gateway.
6. **Composition root** — the only place that constructs infrastructure.

### Rules

- Domain imports domain only.
- Application services import public service contracts, never another module’s repository, models, migrations or `internal/`.
- Infrastructure imports domain and ports; only the composition root constructs it.
- Interfaces import application services, never repositories.
- Agent tools call the gateway; the gateway calls services; no direct DB or filesystem.
- CLI commands call services; no business logic, no SQLAlchemy.
- Electron renderer imports the preload API only; no Node, database, filesystem or secrets.
- Electron main owns OS integration and the device key; not legal records.
- No module writes another module’s tables.
- No cycles. No global orchestrator. No god file.
- Court-specific code lives only in `forum_adapters` or corpus data.

### Public and private

- Public per module: `api.py`, `contracts.py`, `service.py`, shared DTOs.
- Private: `models.py`, `repository.py`, `mappers.py`, `internal/`, migrations, SQL and tests.
- The table-ownership manifest names one owner per table.

### CI enforcement

- `import-linter` layers and independence contracts.
- `ruff` banned imports for wrong-layer FastAPI/SQLAlchemy/Pydantic AI/Electron use.
- `mypy --strict` on domain and application services.
- Table ownership: every table has exactly one owner.
- Schema drift: SQLAlchemy models match the baseline.
- Tool/catalog parity.
- CLI/route/tool parity.
- No cycles.
- Renderer boundary.
- No-god-file check.
- No court-specific code in domain or application services.

### Database, filesystem and Electron

- **Database:** only infrastructure repositories. Application services use ports. No route, CLI command, tool, renderer, domain object or agent touches SQLAlchemy.
- **Filesystem:** storage adapter, builder, OCR/worker, x2t subprocess and Electron main. Renderer has none.
- **Electron:** main and preload only. Renderer uses `contextBridge` with `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`.
- **Agent:** no database, no filesystem, no Electron.

---

## 7. Editor and document authority

- V1 uses the embedded Windows-native Euro-Office editor and `x2t`; there is no shared live session and no `DocService` process.
- One active `editing_session` is the edit lease. Only its holder may save. Another user who opens the document reads the latest committed version.
- A save carries the lease, base version and base hash. The service locks the document row, verifies both, creates an immutable `document_version` and updates the current pointer. A moved base is `DOC_STALE_BASE`; a lost lease is `DOC_SESSION_REVOKED`.
- Agents submit base-bound `document_proposal` rows; they do not hold the human edit lease and cannot apply while it is active.
- There is no server checkpoint and no `editor_recovery` version. A restore creates a new version from an old blob and resets approval.
- The builder is the sole agent/offline DOCX mutator; `docx-core` is read/verify only. Reading for verification goes to the OOXML package directly (`lxml`), not through the editor API.
- The editor gets no database credential; MavrykX owns identity, versions, permissions, approvals and audit.
- A future live co-editing decision may implement the same edit-lease and save seam. V1 does not add CRDT, OT, cursors or a second document authority.

---

## 8. Deployment and operations

- Signed Windows installer for the desktop; signed Windows/Linux server installer. No Docker dependency; a development machine may use a disposable PostgreSQL container for tests, never the product.
- Bundled PostgreSQL, localhost-only; clients talk to the API, never the database.
- Blobs content-addressed; backup manifest pins DB snapshot, blobs and audit head.
- Encrypted backups; dry-run restore; quarterly drill.
- Remote connection service: rendezvous + E2E relay; the firm server still authenticates and authorises.
- Observability: OpenTelemetry spans for model and tool calls; legal audit is separate from the execution trace.

---

## 9. Build order

This is engineering sequence, not product releases. Steps 1–6 are the legal CRM and shared Matter workspace. Step 7 is Maverick's AI Legal Harness. Step 8 is the first end-to-end legal workflow.

**Step 0 — verification spine (exists).** The scaffold, operation registry, boundary checks, baseline schema, RLS probes and `tools.verify` gate. Every later step keeps them green.

1. **Firm, users, memberships and roles.** Firm bootstrap, admin/lawyer/staff membership, Matter `lead`/`editor`/`viewer`/`approver`, sessions, devices and the audit actor. Gate: a firm admin without Matter membership reads no Matter content.
2. **Clients, contacts and Matters.** Contact deduplication, client with many Matters, Matter open/close, the matter-open gate, parties and notes-first intake. Gate: a client with two Matters is isolated; a Matter can exist with a note and no client.
3. **Shared Matter workspace and resource permissions.** Sections, membership, private/shared/restricted visibility, resource grants, walls, the one access policy, the workspace change feed and cross-resource audit. Gate: cross-Matter and private-content negative tests pass for every resource type.
4. **Documents, Euro-Office, versions and audit.** Upload, local editor, edit lease, base-bound save, immutable versions, compare, restore, tracked changes, proposals and hash-bound approval. Gate: two users edit sequentially with no silent overwrite; a stale save is refused.
5. **Notes, tasks, assignments, events and conversations.** Notes with headings, tasks and assignments, deadlines, appointments/hearings, conversations and messages, and research submissions as task + version + approval. Gate: every resource is attributed and audited.
6. **Review and approval workflows.** Submission, supervisor review, approve/return, notifications, the review inbox and the document status transitions. Gate: an intern submits, a supervisor returns, a new version is submitted and approved; the original survives.
7. **Maverick AI Legal Harness on the completed CRM.** Tool catalog, gateway, bundles, context assembly, runs, proposals, approvals and the agent UI. The harness calls the CRM services; it adds no legal authority and no second data path. Gate: an intern's agent reads only the intern's resources and cannot approve.
8. **First end-to-end legal workflow.** Pleading ingestion → fact extraction → legal research → memo drafting → lawyer review. This is the first legal-intelligence proof, not the first build step. Gate: a lawyer completes the workflow on a real Matter, every citation is verified or `unconfirmed`, and the memo is approved by a human.

**Do not start step 7 before steps 1–6 pass their gates.** The CRM is not a demo for the agent; the agent is a later participant in a working firm product. A lawyer must be able to run a Matter with documents, notes, tasks, events, conversations and review without a model in the room.

---

## 10. Acceptance gates

**CRM and shared workspace.**

- A firm has an admin, at least two lawyers and a staff/intern; roles and Matter access are enforced; a firm admin outside the Matter reads nothing.
- A client holds two Matters; documents, notes, tasks, events, conversations and approvals never cross the Matter boundary.
- Two lawyers and an intern work in one Matter. Each sees the latest saved shared state and the attribution for every change.
- One user holds the document edit lease; another reads the latest version; a stale save is refused; the next save creates one immutable version.
- A lease expires or is revoked; the next user can edit; an old save does not overwrite the new version.
- Version comparison is read-only; restoring an old version creates a new version and resets approval.
- A private note and private conversation are invisible to every other Matter member, including a `lead` or `approver`; a private task is visible only to its creator and assignee.
- An intern submits; the supervisor returns and later approves; the original version survives; every step is audited.
- An agent proposal against a stale base is detected; it never overwrites a human save or the current version.
- Every workspace resource write has an audit event; a missing event fails a fixture.
- A document can be worked without a model, a run or a bundle. The CRM is complete before step 7.

**Legal intelligence and agent.**

- A matter with an ambiguous “Supreme Court case” folder does not become an SLP.
- A primary-law instrument has a source, snapshot, version and reviewer; a stale rule is `unconfirmed`.
- A case-law quote and pinpoint are verified deterministically.
- A library item is admin-published and invisible without a grant.
- A user browser and agent browser are separate; a handoff is visible and revocable.
- A workflow run pins its definition version; a legal gate cannot be cleared by the graph.
- An intern's agent inherits the intern's grants, cannot read a restricted document and cannot approve.
- Import layers, table ownership, renderer isolation and no-god-file checks fail a broken fixture.

**Schema smoke test (executed).** On PostgreSQL 17.12 + pgvector, `0001_core.sql` runs from empty and `0002_rls_test.sql` passes: 97 `app` tables, 0 without RLS, 0 `matter_id` tables without a policy; the isolation, wall, application-tree and audit-chain probes pass. The workspace step adds no table for a section; it uses `folder`. The private-note, private-task and private-trace policy narrowing is a forward migration and must land before those resources are exposed.

---

## 11. Deferred

- Real-time co-editing, shared cursors, presence and simultaneous editing.
- DocumentServer shared sessions and peer-hosted editor services.
- Filing portal attempt/confirmation.
- Live agent participation inside the editor.
- Email as a first-class communication record.
- External counsel guest accounts.
- Firm-scoped Research Studio.
- Teams, billing, time recording and a client portal.

The CRM and workspace decisions are closed for V1. The live co-editing option is explicitly deferred; the edit-lease and save seam remains so it can be revisited without a second document authority. Implementation details — forum adapter protocol, source list, sync cadence, browser handoff, licensing, workflow spec format, source ownership — are recorded in `docs/implementation/` and the owning module; they do not reopen the architecture.

The domain model is in [02-domain-model.md](02-domain-model.md). Application, agent and data are in [03-application-agent-and-data.md](03-application-agent-and-data.md). Shared collaboration is in [04-shared-workspaces-and-collaboration.md](04-shared-workspaces-and-collaboration.md). The product surface is in [05-product-experience.md](05-product-experience.md).
