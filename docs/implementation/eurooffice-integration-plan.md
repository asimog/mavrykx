# MavrykX — Euro-Office integration plan

**Status:** current · **Version:** 1 · **Date:** 2026-11-28

Euro-Office 9.3.8 only. No other editor distribution is used, bundled or referenced by this plan.

**V1 scope.** The CRM and shared Matter workspace use the embedded Windows-native Euro-Office editor and `x2t`. Document editing is sequential: one edit lease per document, saves through the MavrykX API, immutable versions, no live co-editing. V1 starts no `DocService`, has no hosted DocumentServer and has no Docker dependency. The shared live-session material in this plan is retained as a deferred option and is not part of the CRM build order.

---

## 1. Decisions

- **Editor:** Euro-Office 9.3.8, DesktopEditors `v9.3.8` (`e681296d8173`) and DocumentServer `v9.3.8`.
- **Packaging:** target one Electron installer, roughly 3 GB installed. It carries the local editor, `x2t`, and the server pack - DocService, FileConverter, PostgreSQL 17.12 and the PostgreSQL queue adapter. No RabbitMQ, no Erlang. Server components are installed but not started in V1.
- **V1 mode:** local editing only. A document is edited by one user at a time under an edit lease; other authorised users read the latest saved version. Co-editing, peer-hosted sharing and DocumentServer sessions are deferred.
- **Fidelity:** DOCX round-trip fidelity is a hard requirement. Euro-Office is the editor; there is no CRDT layer, no alternate editor and no converted format as the record.
- **Database:** PostgreSQL 17.12 is bundled and run as a child process under the user account, with data in `ProgramData`. The development machine's 18.1 instance on 5433 is a convenience, not the product.
- **Reductions:** English only, no presentation, no Visio, no AdminPanel, Metrics or npm payload.
- **Approval:** the agent may request approval; only a logged-in human with the right role may grant it, and the server records the grant.

---

## 2. The two editor modes

Local is the V1 mode. The collaborating mode is retained as a deferred option, not built in the CRM sequence. They share one pinned frontend build but run in different containers.

| | Local workspace editor (V1) | Collaborating workspace editor (deferred) |
|---|---|---|
| Users | One | Two or more in a shared workspace |
| Host | The client app — Electron or the local web host | `DocService` on the shared machine |
| Editor mode | Desktop mode, `targetApp: 'desktop'`, `url: '_offline_'` | Web mode over the Docs API |
| Documents | Bytes passed in-process | Fetched by `DocService` from a short-lived URL |
| Services | None | `DocService`, `FileConverter`, PostgreSQL adapter |
| Conversion | Local `x2t.exe` | Server `x2t.exe` through `FileConverter` |
| Save | `asc_nativeGetFile3` → MavrykX API → version | Callback → MavrykX API → version |
| Review/approval | On the saved version | At commit |
| Failure scope | One user | The live session |

Local mode is the openadvo/advdsh pattern: the editor is embedded and no server process exists. Shared mode is the only place a live session, and therefore the only place a lost session, can occur.

Do not mix files between the two builds. The desktop package and the server package are both 9.3.8, but they are compiled separately; copy `web-apps`, `sdkjs` or `x2t` between them and saves can corrupt.

### 2.1 V1 sequential editing

The embedded editor opens a committed base version under an `editing_session` lease. The lease holder is the only user who may save. Another user who opens the document gets the latest committed version read-only.

A save carries the lease id, base version, base hash and an idempotency key. The API locks the document row, verifies the lease and base, stores the blob and creates an immutable `document_version`. A moved base is `DOC_STALE_BASE`; a lost lease is `DOC_SESSION_REVOKED`. The lease is released on close, expires on a missed heartbeat or is revoked by a firm admin or the responsible lawyer. There is no server checkpoint and no live buffer.

**Peer-hosted sharing (deferred).** Any client could host. When a user shares a workspace, that client starts the bundled server pack, binds the host page and `DocService` to the LAN, and issues an invitation carrying host, port and a one-time token. The other user joins from their own client. When the last participant leaves or the host stops sharing, the server pack stops. A share is a session, not a service: the host's app must stay open and the machine awake. This paragraph is retained for the deferred option and is not a V1 requirement.

---

## 3. Windows reality

Euro-Office publishes deb/rpm packages and a container image for 9.3.8. **It publishes no Windows executable for any release.** What exists in the repository is:

- `Common/config/production-windows.json` — Windows paths, `C:\Windows\Fonts`, `x2t.exe`, static content.
- `allfontsgen.bat` — font-list generation on Windows.
- `document-server-package/exe` - an Inno Setup recipe with WinSW service definitions and a prerequisite list (PostgreSQL 18.1 in the recipe; we pin 17.12, Redis 7.4, Erlang + RabbitMQ 4.2.1, OpenSSL, VC redists). That is the recipe's list, not this plan's; we use neither RabbitMQ nor Redis.
- `Makefile` Windows branches (`PLATFORM := win`, `EXEC_EXT := .exe`).

For the deferred shared mode, Option B runs the Euro-Office Node services from source on Windows. That combination is not vendor-published, so we would own it: pinned versions, a smoke test after every change, and no expectation of upstream Windows fixes. V1 does not run those services; it uses the DesktopEditors package and `x2t`. The Inno recipe stays available if a packaged installer is wanted later; it would be built from these same Euro-Office files.

---

## 4. Components

### Local tree (per client)

`editors/` and `converter/` from the Euro-Office 9.3.8 desktop package, reduced:

- `web-apps/apps/{api,common,documenteditor,spreadsheeteditor,pdfeditor}`
- `sdkjs/{common,word,cell,pdf,vendor}`
- `web-apps/vendor`
- `converter/` with `x2t.exe`, DLLs, `templates/EN`, `empty/{en-GB,en-US,default}`
- `fonts/`, `dictionaries/en_*`
- generated `AllFonts.js` and `font_selection.bin`

Removed: `presentationeditor`, `sdkjs/slide`, `visioeditor`, `sdkjs/visio`, non-English locales, help, dictionaries, templates, empty templates and formula names.

Size: **345.9 MB** from 1,031.3 MB.

### Shared tree (server)

`web-apps/`, `sdkjs/`, `server/`, `core-fonts/`, `dictionaries/`, `document-templates/` from the Euro-Office 9.3.8 DocumentServer package, with the same language and editor removals, plus:

- removed `server/AdminPanel` (143.8 MB)
- removed `server/Metrics` (71.3 MB)
- removed `npm/json` (49.1 MB)
- no `allthemesgen` run, because presentation is gone

Size: **1,163.8 MB** from 1,931.4 MB.

---

## 5. Runtime topology

V1 is local:

```
Electron
  ├─ React workspace
  ├─ embedded Euro-Office editor
  ├─ x2t.exe + DLLs + AllFonts.js + font_selection.bin
  └─ MavrykX API / PostgreSQL / blob store
```

No `DocService`, no `FileConverter`, no editor queue and no server pack process runs. The editor saves through the API.

The shared topology below is **deferred** and is not part of V1.

```
Electron main process (supervisor)
  ├─ MavrykX API        local FastAPI, LAN TLS while sharing
  ├─ host page, short-lived download URLs, callback, approval, versions
  ├─ reverse proxy      /web-apps /sdkjs /coauthoring → DocService
  ├─ DocService         node, ephemeral port, NODE_ENV=production-windows
  ├─ FileConverter      node workers
  ├─ queue + pub/sub    PostgreSQL adapter, in-process
  ├─ PostgreSQL 17.12   bundled binaries, data in ProgramData
  └─ x2t.exe + DLLs + AllFonts.js + font_selection.bin
```

`DocService` serves the editor files itself (`static_content` in `production-windows.json`), so nginx is not required. MavrykX's own server fronts it for TLS and origin control.

Start order: PostgreSQL → adapter schema → FileConverter → DocService → MavrykX API.

### 5.1 Supervision

Electron owns the lifecycle. Nothing runs at login.

- **Start.** On “Share workspace”: choose free ports, start PostgreSQL with `pg_ctl`, wait for `pg_isready`, ensure the adapter schema, start FileConverter, start `DocService`, probe the editor, then expose the host page.
- **Stop.** On “Stop sharing” or when the last participant leaves: stop `DocService`, FileConverter, then PostgreSQL with `pg_ctl stop -m fast` — reverse order of start.
- **Crash.** Restart a component with backoff, show its state in the tray, and end the session if the database cannot recover.
- **Awake.** `powerSaveBlocker` while sharing; warn on battery or imminent sleep.
- **Ports.** Ephemeral; the firewall rule is scoped to the app executable, not a fixed port.
- **No elevation.** Child processes run as the user. Only the installer needs administrator rights, for the firewall rule and the VC++ runtime.
- **Single instance.** One stack per machine, enforced by an app lock.

Supervision is process management, not a service manager: nothing runs at login, and if the app quits or
the user logs out, the share ends. That is deliberate. No Windows service and no Inno Setup are installed.

---

## 6. Services

### PostgreSQL

Bundled PostgreSQL 17.12 binaries, the V1 baseline. The Euro-Office Windows recipe targets 18.1; the product baseline stays 17.12. It is not installed as a Windows service.

- Started by Electron with `pg_ctl start`, stopped with `pg_ctl stop -m fast`.
- Data directory under `ProgramData\MavrykX\pgsql`, initialised on first share.
- Separate port from any other PostgreSQL on the machine; the development instance on 5433 is unrelated.
- Role `onlyoffice`, database `onlyoffice`, password generated at install and kept in the Windows credential store and `local.json`, never in git.

### Queue and pub/sub

RabbitMQ and ActiveMQ are both rejected. RabbitMQ brings Erlang, a second service and a 10–20 second start; ActiveMQ brings a JVM. Neither fits an app that becomes a server on demand.

The queue is PostgreSQL, selected by `queue.type: "postgres"`, implemented in `vendor/euro-office/pg-adapter/` and covered by `test/smoke.js`:

- `taskqueuePostgres.js` replaces `Common/sources/taskqueueRabbitMQ.js`.
- `pubsubPostgres.js` replaces `DocService/sources/pubsubRabbitMQ.js`.
- One table for messages and one for pub/sub; `FOR UPDATE SKIP LOCKED`, visibility timeout, attempts, dead letters, TTL and delayed delivery.
- No extra runtime, no extra port, no Erlang; the connection reuses `services.CoAuthoring.sql`.

Wiring, configuration and limits are in `vendor/euro-office/pg-adapter/README.md`.

### Node

Not required on the machine if `DocService` and `FileConverter` are built with `pkg`. If the deferred
shared mode runs them from source instead, pin **Node 22**; the repository's build Node 26.13.1 and
Electron's Node 24.22.3 are not that runtime.

### Optional, not installed

- Redis — not installed. `editorDataStorage` defaults to `editorDataMemory`; if DocService is ever run multi-process, session state must move to Redis and be tested.
- SpellChecker — separate service needing `nodehun`; skip it. The editor checks spelling in the browser, and the English dictionaries ship.

---

## 7. Configuration

One `local.json` beside `default.json`, loaded through `NODE_CONFIG_DIR`.

```jsonc
{
  "services": {
    "CoAuthoring": {
      "server": { "port": 8000 },
      "sql": { "type": "postgres", "dbHost": "127.0.0.1", "dbPort": 5432,
               "dbName": "onlyoffice", "dbUser": "onlyoffice", "dbPass": "<secret>" }
    }
  },
  "queue": {
    "type": "postgres",
    "visibilityTimeout": 300,
    "retentionPeriod": 900,
    "postgres": { "pollInterval": 200, "prefetch": 1 }
  },
  "storage": { "fs": { "folderPath": "D:/MavrykX/euro-office/cache" } },
  "FileConverter": {
    "converter": { "x2tPath": "../FileConverter/bin/x2t.exe",
                   "fontDir": "C:/Windows/Fonts" }
  }
}
```

The adapter's connection comes from `services.CoAuthoring.sql`; no separate block. The development machine's 5433 instance is not the product port.

The JWT secret is shared with MavrykX's server and never sent to the browser except inside a signed editor config.

---

## 8. Integration contract

The shared-session contract below is **deferred**. V1 uses the local editor contract: open a committed base under a lease, edit in-process, save bytes to the MavrykX API with the lease and base hash, receive a new immutable version.

The deferred editor contract is the one the Euro-Office `document-server-integration` examples implement; MavrykX would reimplement it in its own server rather than running the example app.

1. **Open.** MavrykX serves a host page for one document. The page loads `api.js` from `DocService` and calls `DocsAPI.DocEditor(id, config)`.
2. **Config.** `document.url` is a short-lived, single-use download URL; `callbackUrl` is MavrykX's callback; `document.key` identifies the document and revision; the whole config is signed as a token.
3. **Load.** `DocService` fetches the document, opens a session, and streams changes to every connected browser.
4. **Save.** `DocService` posts to the callback with a status: 1 editing, 2 must save, 3 corrupted, 6 force save, 7 corrupted force save. MavrykX validates the token and the key, stores the bytes, and answers 200 or 500.
5. **Convert.** Conversion goes through `FileConverter`, which spawns `x2t.exe`; the result returns over the same callback or the command service.

Every callback is rejected unless the token verifies and the key is one MavrykX issued.

---

## 9. Approval

Two different acts, two different authorities.

- **Accepting a tracked change** is a document edit. The agent may perform it when the user has said so.
- **Approving a version** is a legal act. Only a human with the approving role may do it, and the server records it.

The intended workflow — "user tells the agent to approve all changes" — is preserved, but the permission is not a sentence in the prompt. It is a grant:

1. The user asks the agent to approve the changes.
2. The client shows the exact change set, base revision and document hash, and asks the user to confirm.
3. On confirmation the server issues a one-time approval grant bound to the user, the document, the base revision, the change-set hash and an expiry.
4. The agent executes accept/commit with that grant.
5. The server validates the grant, writes the approval row (actor, role, document, hash, time, rationale) and creates the immutable version.

An agent without a grant can propose, diff and request. It cannot accept, commit or approve. A tool-schema check is not the lock; the server is.

In a multi-user Matter, a firm admin or a lawyer with Matter `edit` access reviews and approves; the author does not approve their own submission where another eligible reviewer exists. In a one-person firm the sole practitioner may self-approve, recorded as a self-review with the same version hash and audit. An agent never approves.

---

## 10. Verification

The V1 checks below are the document-step acceptance list; run them when the step is built.

1. Open and edit DOCX; styles, tables, numbering and headers survive.
2. Save and reopen DOCX in Word.
3. Open and edit XLSX; formulas, formatting and sheets survive.
4. Save and reopen XLSX.
5. Open and view PDF; text and pages match.
6. Font list loads; no missing-font errors.
7. DOCX → PDF and XLSX → PDF through `x2t`.
8. Local mode: editor opens offline with no services running.
9. Two users open one document; the first holds the edit lease and the second reads the latest version.
10. A save creates one immutable version; the second user sees it on refresh.
11. A save against a moved base is refused with `DOC_STALE_BASE`; no version is created.
12. A lease expiry or revocation refuses the old holder's next save.
13. Compare two versions read-only; restore an old version as a new version.
14. A stale agent proposal never overwrites a human save.
15. An agent without a grant cannot commit or approve.
16. An approval is single-use, expires and is bound to the version hash; a return reopens the task without deleting the version.
17. No `DocService`, hosted DocumentServer or Docker process is required.

The deferred shared-session checks are: two browsers edit one document in a live session; a callback from an unknown key is rejected; the shared host survives a browser refresh. They are not V1 gates.

---

## 11. Risks

- **Version coupling.** `web-apps`, `sdkjs` and `x2t` must be the same 9.3.8 build. Mixing corrupts saves. Pin all three and verify on every change.
- **From-source Windows run (deferred shared mode).** Not vendor-tested. Own the smoke test.
- **Compiled dependencies.** `sharp` usually has Windows binaries; `oracledb` is unused with PostgreSQL; `nodehun` is skipped.
- **The queue adapter is ours (deferred shared mode).** It is tested but not upstream-tested. Re-run `test/smoke.js` after every Euro-Office upgrade, and review `schema.sql` before applying it to an existing database.
- **Shared host availability (deferred).** A shared session dies if the host sleeps or reboots. Use the always-on machine.
- **Network exposure (deferred).** Bind to the LAN, terminate TLS in MavrykX, keep the token secret server-side, issue short-lived single-use URLs.
- **Permissions are UX.** The editor setting does not authenticate anyone; the API lease, base hash and RLS do.
- **Fonts.** Without generated `AllFonts.js` and `font_selection.bin`, pagination and PDF output drift from Word.
- **Windows edges.** Case-only name collisions, paths over 260 characters, spaces and non-English names, antivirus scanning large DLLs, file locks on save.

---

## 12. Build order

This is the document-step sub-order within [architecture step 4](../v1/01-architecture.md) §9; it is not
the product build order. V1, in the CRM document step:

1. PostgreSQL 17.12 native on a free port (the example uses 5432), role and database created. The current 18.1 instance on 5433 is a development convenience; CI and the installer use 17.12.
2. Reduced local editor tree staged and verified against the 9.3.8 pins.
3. `x2t.exe` local; DOCX round-trip and PDF conversion pass.
4. Embedded editor opens a committed base under an edit lease.
5. Save creates an immutable version; the current pointer moves; audit records the actor and hashes.
6. Two-user sequential editing and stale-save refusal.
7. Compare and restore; approval reset.
8. Tracked changes, approval grant, commit, review return.
9. Run the V1 verification list, then reduce nothing further without re-running it.

The shared-session build (PostgreSQL adapter schema, Node 22 services, `DocService`, `FileConverter`, host page, callback) is deferred and is not part of the CRM sequence.

---

## 13. Open items

V1:

- Confirm the local editor package and `x2t` are the same 9.3.8 build on every installer.
- Choose the version-comparison implementation; it reads immutable versions and never writes a version.
- Confirm the lease heartbeat and expiry defaults with a real two-user session.

Deferred shared session:

- Confirm the shared host is the always-on machine, not a laptop.
- Confirm the adapter passes `test/smoke.js` on the target machine before the first share.
- Decide whether the native PostgreSQL instance replaces the Docker one, or stays on 5433.
- Decide when the Inno Setup package is built from these same files, if at all.
