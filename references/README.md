# MavrykX — Reference repositories

**Status:** current · **Version:** 1 · **Date:** 2026-11-28

Two external repositories were studied for the CRM and shared-workspace design. They are **reference only**. They are not vendored, imported, built, linked, submoduled or shipped with MavrykX, and no upstream code is copied into this repository.

The clones live outside the source tree at `C:/dev/reference/`. The pins, licences and test results are recorded here and in [`manifest.json`](manifest.json). The licence texts are in [`licenses/`](licenses/).

The clones are intentionally not committed: the clone directories total about 56 MB (Kosmos) and 938 MB (Stella) including git metadata, and a submodule would make the product checkout depend on two upstream repositories. This file, the manifest and the licence texts are the committed reference record; the clones are the archive.

| Reference | Pin | Release | Licence | Stack |
|---|---|---|---|---|
| [Kosmos](https://github.com/Kosmos-Law/kosmos) | `699556325f69aa7c39c7a0f8b00e127faedd3490` on `dev` | No tagged release; 2026-11-22 | AGPL-3.0 | Python 3.13, Django 4.2, PostgreSQL |
| [Stella](https://github.com/stella/stella) | `0322889e3861dcb6807dd12a7cbe48504077af44` at `v0.9.93` | `v0.9.93`, 2026-11-27 | Apache-2.0 | Bun, TypeScript, PostgreSQL, React, Tauri |

Stella's submodules are part of the pin: `.ai/shared` at `b1289e96d1e8f8f7bf2f0b67cef6e3992e02d840` and `packages/template-packs/content` at `6abcec0fbd61651ed8b70c407a4b0c3f80570d0f`.

---

## 1. Kosmos — Clio-style CRM and practice management

Kosmos is a working Django practice manager. It is useful as a **CRM behaviour reference**, not as a code or permission model. It has no tags or releases; the latest `dev` commit is the study point.

### What it gets right

- **One firm, contacts and Matters.** A firm row, users, firm-wide contacts and Matters with an optional client. A Matter can exist with a note alone.
- **Party matrix.** `Contact` is the party record; `Relationship(matter, contact, role, group)` gives a Matter-specific party list; `Group` is global or Matter-specific; `Role` is global. `Matter.client` is canonical and mirrored into protected system Client rows.
- **Derived client status.** Client status is computed from the client's Matters, not stored separately. The same rule drives badges and filters.
- **Lifecycle side effects.** Closing a Matter stamps the end date and concludes its proceedings; reopening reverses the date. The transition owns its downstream state.
- **Assignor-owned due dates.** A task has one assignee plus `assigned_by`; only the assignor or an admin may move the due date. This prevents an assignee silently extending a deadline.
- **Access tests as a matrix.** A route-by-route permission document and `test_*_access.py` files cover the surfaces. The tab and route lookup registries make the Matter boundary explicit for routes that name records by id.

### What not to copy

- **Permissions are all-or-nothing.** Admin, `perm_all_matters` or `Matter.members`; the firm-wide flag defaults on. There are no Matter roles, ethical walls, per-document ACLs, private resources or RLS.
- **Audit is mutable history.** `django-simple-history` rows can be pruned and there is no read or download trail.
- **Documents are PDF-only and destructive.** OCR replaces the stored file at the same path; there is no version model, retained original, lock or base-bound save.
- **No legal review.** Only time entries have approval, and self-approval is allowed. There is no hash-bound review of legal work product.
- **No generic section or heading model.** The `/case/` tabs are a UI registry; they arrange records but do not own them.

### Tests actually run

Kosmos was run in a temporary virtual environment outside the clone (`UV_PROJECT_ENVIRONMENT` under `%TEMP%`), not in the clone. The clone has no `config/.env`; the run set dummy `SECRET_KEY`, `DEBUG`, `ENV`, `ALLOWED_HOSTS` and `DB_*` values. The database suite is the only part that uses the database.

| Command | Result |
|---|---|
| `uv run --frozen pytest --collect-only -q -p no:cacheprovider` | 3,455 tests collected in 9.10 s; 316 files |
| `uv run --frozen pytest apps/drafts/tests/test_redline.py config/tests/test_safe_markdown.py -q -p no:cacheprovider` | 40 passed, 12 skipped in 0.39 s; skips are LibreOffice/UNO |
| `uv run --frozen pytest apps/matters/tests/test_matter_lifecycle.py -q -p no:cacheprovider` | 18 errors; PostgreSQL unavailable at `localhost:5432` |
| `uv run --frozen lint-imports` | 4 contracts kept, 0 broken |

WeasyPrint required a temporary import stub because GTK/Pango is absent. The database suite was not run; the local PostgreSQL 18 install has no `vector.control`, and Docker was not running. These are environment blocks, not product results.

---

## 2. Stella — legal workspace, documents, agents and approvals

Stella is a broad TypeScript legal workspace. It is the stronger reference for **workspace resources, version fencing, audit and agent approvals**. It supports both sequential and real-time editing; MavrykX V1 adopts only the sequential discipline.

### Workspace and resources

- **Organisation → workspace (Matter) → entity.** Almost everything inside a Matter is an `entity`: document, folder, task, message or link. A document is not a separate table; a folder is the same table with `kind = 'folder'`.
- **Immutable versions with a current pointer.** `entity_versions` holds the immutable header; `entities.currentVersionId` is the pointer. A file field points at object storage by SHA-256.
- **Typed properties.** `properties` defines file, text, select, date, int, money and person fields per Matter; `fields` is one row per `(property, version)`. The model is portable and testable.
- **Contacts and members.** Matter contacts carry roles (opposing party, counsel, witness, expert, judge, mediator, other); Matter members carry assignments.
- **Lists and review.** Legal lists use sections, columns and items; a fact item points at a source **entity version** with locator, quote and verification status. Source decisions are immutable.
- **No first-class note.** A note is a task description, a document or chat. That is a gap against MavrykX's note-first intake.

### Permissions and audit

- **Three layers.** Organisation role matrix; Matter visibility (`all_members`, `admins_and_assigned`, `assigned_only`) plus membership; credential attenuation (role AND API-key scope).
- **One visibility rule in SQL.** `stella_authorized_workspace_ids` and the security-barrier view are reused by RLS; the API and SQL copies are bound by tests. This is the pattern MavrykX adopts.
- **Append-only audit.** `audit_logs` records performer type (`user`/`agent`/`service`), trigger (`direct`/`agent_delegation`/`schedule`), run id, approval status and approver. The app role can insert and select, not update or delete.
- **Private content exists** for reader annotations, skills and per-user chat threads. Matter visibility still lets owners/admins see wider Matters. MavrykX does not adopt this: its notes, tasks and conversations are Matter-wide.

### Documents and collaboration

- **Sequential path.** `desktop_edit_sessions` has a base version, token hash, TTL, checkpoint, takeover request and finalisation into an immutable version. A partial unique index allows one open session per user/entity/property; a lead may force takeover.
- **Write fencing.** `write-file-version.ts` is the single version writer; all but replace-current require `expectedCurrentVersionId`; a mismatch returns `current-version-changed`; a live session returns `edit-session-open`.
- **Real-time path.** Opt-in Yjs CRDT over Hocuspocus, with a 15-second Redis authority lease and explicit publish into an immutable version. The live room is not the record.
- **Comparison and review.** Stored versions can be compared as tracked-change DOCX. Review findings are distinct from edits; a finding row is current state, a decision table is the audit spine; a review pins an approved playbook version.
- **AI proposals.** `docx_suggestions` are pending/accepted/rejected operations with comments, severity and source scope.

### Agents and approvals

- **Tool policy kinds.** `internal`, `mutation`, `external`, `publicOfficial`, `scopeExpansion`; a missing policy fails closed.
- **Standing grants.** `chat_tool_grants` with scope `conversation` or `always` and policy `grantable`, `approve-once` or `never-auto`. A grant removes a gate only where policy allows.
- **Dispatch before execute.** A `dispatched` audit row is written before the tool runs; if it cannot be written, the tool does not run. Arguments and results are not stored.
- **Subagents cannot widen authority.** They run only ungated tools; gated calls return as proposals.
- **Review gate.** A workflow review gate raises a task; settling the gate settles the task, and completing the task settles the gate.
- **Source-version evidence.** Citations point at a source version, locator and quote; invalid generated citations are withheld; per-turn refs neutralise fabricated citations; AI output carries `dataWorkspaceIds`/`sourceDataWorkspaceIds` so it cannot outlive access to its sources.

### Tests actually run

No dependencies were installed in the clone. Bun 1.4.5 was installed outside the repository; the repo pins 1.4.4, and the patch difference did not affect these dependency-free tests.

| Command, from the Stella clone | Result |
|---|---|
| `bun test packages/workspace-model/src/views.test.ts packages/workspace-model/src/properties.test.ts` | 12 pass, 0 fail, 192 ms |
| `bun test scripts/check-policy-evidence.test.ts` | 5 pass, 0 fail |
| `bun test packages/concurrency/src/event-loop.test.ts` | 2 pass, 0 fail |
| `bun test packages/auth-model/src/invitation-sections.test.ts packages/auth-model/src/opaque-organization-slug.test.ts` | 14 pass, 0 fail |
| `bun test packages/concurrency/src` | 2 pass, 8 fail, 8 errors; missing workspace modules (`@stll/property-testing`, `@stll/test-kit`) because `node_modules` is absent |
| `bun test packages/auth-model/src` | 14 pass, 1 fail, 1 error; `better-auth/db` is absent |

A full typecheck and database test were not attempted; they need a full install, generated sources and PostgreSQL. The dependency-free core passed; the full build path was not exercised.

---

## 3. What MavrykX adopted

- **CRM first.** Kosmos confirms that the Matter-management substrate is a product on its own; Stella confirms that the agent is a later layer. The build order in `01-architecture.md` puts firm, clients, Matters, workspace, documents, work and review before the harness.
- **Simple firm hierarchy.** MavrykX keeps `matter_member` with `edit`/`view`, no ethical wall, and `resource_grant` for restricted documents. A firm admin reads every Matter and assigns Matter access to lawyers, staff and interns.
- **No private resources.** MavrykX makes notes, tasks and conversations Matter-wide. This is deliberately simpler than Stella's private chat threads.
- **Immutable versions and a current pointer.** MavrykX already had this; Stella's `expectedCurrentVersionId` and single-writer session sharpen the sequential save contract.
- **One edit lease, base-bound save.** The lease and stale-save refusal are MavrykX's answer to Kosmos's last-write-wins and Stella's per-user/takeover session. MavrykX keeps the explicit takeover idea but drops Stella's server checkpoint; the local editor owns the unsaved buffer.
- **Write contracts and revisions.** The `patch`/`replace` precondition and opaque revision token in `03-application-agent-and-data.md` come from Stella's write-contract check.
- **Dispatch-before-execute audit.** The tool gateway writes the dispatched event first and refuses to run if it cannot.
- **Tool policy and standing grants.** The policy kinds, `grantable`/`approve-once`/`never-auto` and subagent proposal rule are adopted for the step 7 harness.
- **Review gate.** A review gate raises a task; settling either settles both. This connects the review inbox to the work list.
- **Source-version evidence.** A citation points at a source version, locator and quote, not a mutable document.
- **Assignor-owned due dates and lifecycle side effects.** These Kosmos CRM patterns are now rules for tasks and Matter closure.

## 4. What MavrykX did not adopt

- **AGPL code, templates, CSS, migrations, schema or documentation** from Kosmos. None of it is copied. Behaviour and failure modes were studied; the expression is MavrykX's own.
- **Kosmos's all-or-nothing permissions, mutable history, destructive OCR, PDF-only record, last-write-wins editing or time-entry approval.**
- **Stella's real-time Yjs/Hocuspocus editor.** V1 is sequential Euro-Office; the fencing/publish discipline is retained, the service is not.
- **Stella's conflict-check subsystem.** MavrykX explicitly rejects one; the matter-open gate records client and scope.
- **Stella's Matter-visibility tiers.** `all_members`, `admins_and_assigned` and `assigned_only` are a useful Matter boundary, but MavrykX uses a simple `edit`/`view` Matter grant. A firm admin sees every Matter; there is no private-resource tier.
- **Kosmos's configurable party groups.** The fixed `matter_party` role set is enough for V1; configurable groups are a later migration, not a first-CRM requirement.
- **Stella's generic entity model.** MavrykX keeps typed legal records (document, note, task, event, conversation) because a universal entity table would make the legal invariants shallow.
- **Stella's SaaS surface, migration sprawl, branding, sample matters, template text and case-law corpus.**
- **The `.ai/shared` submodule.** It has no licence file and is all rights reserved by default; no prompts, skills or AGENTS fragments were copied.

## 5. Reuse restrictions

- **Kosmos is AGPL-3.0.** Reading for behaviour, requirements and test scenarios is safe. Copying code, templates, styles, migrations, SQL, comments, icons or substantial documentation is not. A derivative would be AGPL-3.0, which is incompatible with MavrykX's licensing.
- **Stella is Apache-2.0.** Code may be reused with the licence and NOTICE, changed-file notices and no implied endorsement. Apache-2.0 does not grant trademark rights; the Stella name, logo, screenshots and product copy are not reusable.
- **Stella dependencies.** MPL-2.0 components (`lightningcss`, `@resvg/resvg-js`, Rust `symphonia`) carry file-level obligations if modified; `date-holidays` data is CC BY-SA 4.0; OFL fonts have reserved-name rules; the Parakeet model is CC BY 4.0, not Apache-2.0. Folio is a separate Apache-2.0 repository and needs its own notice review.
- **Template packs and sample data.** The content repository is Apache-2.0 at root, but each pack has its own content licence; sample matters, judgments and DOCX fixtures are not automatically code-licensed.
- **No code was merged.** The pins are recorded so a future reader can reproduce the study without treating either repository as a dependency.

## 6. Refreshing the study

The clones are not part of the build. To refresh:

```powershell
git -C C:\dev\reference\kosmos fetch origin
git -C C:\dev\reference\kosmos checkout origin/dev
git -C C:\dev\reference\stella fetch --tags origin
git -C C:\dev\reference\stella checkout v0.9.93
git -C C:\dev\reference\stella submodule update --init --recursive
```

Update `manifest.json`, the pins above and the test results only after re-running the commands. Do not copy upstream files into `references/`; the clone is the archive.

## 7. Open questions

- Kosmos has no releases, so the study point is a moving `dev` commit. Pin the exact commit above; do not describe it as a stable release.
- Stella's full build and database tests remain unexercised in this environment. Treat the dependency-free results as evidence of the model, not of the whole product.
- The Stella `.ai/shared` submodule has no licence. It must not be used as a source until its terms are clarified.
- Neither reference implements MavrykX's Indian litigation layer or its simple firm-admin hierarchy. Those remain MavrykX decisions, not borrowed ones.
