# MavrykX — repository scaffold

**Status:** proposal · **Version:** 1 · **Date:** 2026-11-26

The shape of the repository once code exists. It is a plan, not an implementation; no application
code is created by this document.

---

## 1. Stack and pins

One pin owns each runtime. The lockfile is the evidence, not the prose.

| Layer | Package | Pin | Note |
|---|---|---|---|
| Python | CPython | `>=3.14,<3.15` | lock resolves 3.14.10 |
| Python deps | `uv` | `0.13.10` | lockfile `uv.lock` committed |
| Contracts | `pydantic` | `2.14.4` | strict models |
| Settings | `pydantic-settings` | `2.16.3` | typed configuration |
| Agent runtime | `pydantic-ai-harness` | `0.75.0` | pins `pydantic-ai-slim==2.75.0` |
| Agent runtime | `pydantic-ai-slim` | derived | never declared directly |
| Graph | `pydantic-graph` | derived | versioned with the runtime |
| API | `fastapi` | `0.165.0` | |
| DB | `sqlalchemy` | `2.1.9` | |
| DB driver | `asyncpg` | `0.32.0` | |
| Migrations | `alembic` | `1.20.1` | baseline `0001_core.sql`; forward-only |
| CLI | `typer` | `0.29.3` | |
| UI protocol | `ag-ui-protocol` | `1.0.0` | |
| Telemetry | `opentelemetry-sdk` | `1.45.2` | |
| Logs | `structlog` | `26.1.0` | |
| Tests | `pytest` / `pytest-asyncio` | `9.2.0` / `1.5.0` | |
| Property tests | `hypothesis` | `6.170.17` | invariants and state machines |
| HTTP tests | `httpx` | `0.29.0` | |
| Lint | `ruff` | `0.17.6` | |
| Types | `mypy` | `2.4.1` | strict |
| Layers (Py) | `import-linter` | `2.17` | domain, application, interfaces |
| Coverage | `pytest-cov` | `7.1.0` | |
| Security | `pip-audit` / `npm audit` | `2.10.1` / npm | dependency vulnerabilities; ruff `S` covers code patterns |
| DB | PostgreSQL | `17.12` | target, not a package |
| Vector | `pgvector` | `0.5.1` | |
| Desktop | Electron | `45.5.0` | Chromium `156.0.8078.109`, Node `24.22.3`; bundled Node is the native ABI |
| UI | React / React DOM | `19.3.1` | |
| Routing | `@tanstack/react-router` | `1.170.46` | |
| Data | `@tanstack/react-query` | `5.108.4` | |
| Build | Vite | `8.4.0` | |
| Build | `@vitejs/plugin-react` | `6.3.0` | |
| Build | `electron-vite` | `6.0.0` | Electron + Vite integration |
| Routing build | `@tanstack/router-plugin` | `1.169.0` | latest; peer requires router `^1.170.46`; pin both |
| Types | `@types/node` | `24.19.4` | matches Electron Node `24.22.3` |
| Types | `@types/react` / `@types/react-dom` | `19.3.3` / `19.3.0` | |
| Types | TypeScript | `6.0.3` | `strict`, no implicit `any`; 7.0.2 breaks typescript-eslint 8.74 |
| CSS | Tailwind CSS | `4.3.5` | |
| CSS build | `@tailwindcss/vite` | `4.3.5` | Vite plugin |
| Lint (TS) | `eslint` / `typescript-eslint` / `eslint-plugin-import-x` | `10.15.0` / `8.74.0` / `4.18.1` | type-aware rules |
| Unit tests (TS) | `vitest` / `@testing-library/react` | `5.1.2` / `16.3.3` | |
| E2E | `@playwright/test` | `1.65.1` | Electron |
| Packaging | `electron-builder` | `26.18.0` | |
| Layers (TS) | `dependency-cruiser` | `18.9.0` | renderer and layer rules |
| Agent UI | `@ag-ui/client` | `1.0.5` | |
| Client state | `zustand` | `5.1.0` | UI and session state only; server state stays in Query |
| API types | `openapi-typescript` / `openapi-fetch` | `7.13.0` / `0.17.0` | generated from FastAPI, never hand-written |
| Client validation | `ajv` | `8.20.0` | generated JSON Schema only |
| Forms | `react-hook-form` | `7.92.0` | with generated types |
| OCR | `ocrmypdf` / `pytesseract` | `17.14.2` / `0.3.13` | local by default |
| DOCX read | `lxml` | `6.1.3` | server-side read and verify; Euro-Office renders DOCX and PDF; the builder writes |
| PDF text | `pypdf` | `7.2.0` | BSD; PyMuPDF is AGPL and not used |
| Auth | `argon2-cffi` / `pyotp` | `25.1.0` / `2.12.1` | Argon2id and TOTP |
| HTTP edge | `python-multipart` / `itsdangerous` / `cryptography` | `0.0.34` / `2.2.0` / `50.0.2` | uploads, signed URLs, device keys |
| Email | `aiosmtplib` / `imap-tools` | `5.1.3` / `1.16.0` | deferred |
| Task runner | `just` | pinned in CI | wraps `tools.verify` |
| Observability | `logfire` | `6.0.1` | optional, development only |
| Build runtime | Node | `26.13.1` | build and tooling only; not the Electron ABI |
| Editor | Euro-Office | `9.3.8` | DesktopEditors and DocumentServer |

### Pinning rules

- Pin `pydantic-ai-harness` exactly, with its extras listed in `pyproject.toml`:
  `coder`, `codemode`, `skills`, `dynamic-workflow`, `pgtask`, `logfire`. Add provider extras to
  `pydantic-ai-slim`, never to `pydantic-ai`.
- Do not declare `pydantic-ai`, `pydantic-ai-slim` or `pydantic-graph` as independent dependencies.
  The harness pins the first two; the graph ships with the runtime.
- Electron's bundled Node is the ABI for native modules in the main process. Node 26 is for Vite,
  ESLint and scripts only. Do not assume the two match.
- Python and PostgreSQL are constraints plus a lock, not exact strings in prose.

### Pairs that move together

- `@tanstack/react-router` 1.170.46 with `@tanstack/router-plugin` 1.169.0; the plugin's latest peer
  requires router `^1.170.46`.
- Electron 45.5.0, Node 24.22.3 and `@types/node` 24.19.4; the main process uses this ABI.
- TypeScript 6.0.3 with `typescript-eslint` 8.74.0; 7.0.2 breaks type-aware linting.
- Vite 8.4.0, `@vitejs/plugin-react` 6.3.0, `@tailwindcss/vite` 4.3.5, `electron-vite` 6.0.0 and
  `vitest` 5.1.2.
- ESLint 10.15.0 with `eslint-plugin-import-x` 4.18.1; the old `eslint-plugin-import` stops at 9.

---

## 2. Layout

```text
mavrykx/
├── pyproject.toml            # one Python project, uv-managed
├── uv.lock
├── package.json              # workspace root; scripts only
├── package-lock.json
├── AGENTS.md
├── docs/
│   ├── v1/                   # canonical design set (five documents + schema)
│   ├── agents/               # tracker and domain-doc consumer rules
│   └── implementation/       # approved working plans (not design authority)
├── src/mavrykx/
│   ├── domain/               # pure Python: entities, values, policies
│   ├── application/          # use cases, transactions, authorisation, audit
│   ├── infrastructure/       # PostgreSQL, blobs, browser, editor, providers
│   ├── interfaces/
│   │   ├── api/              # FastAPI routes
│   │   ├── cli/              # Typer commands
│   │   └── tools/            # Pydantic AI tool adapters
│   ├── agent/                # Pydantic AI loop and run context
│   ├── composition/          # AgentComposition, bundle selection
│   └── root/                 # the only construction site
├── modules/                  # one package per owning module
│   └── <module>/
│       ├── api.py            # public contracts
│       ├── contracts.py      # DTOs
│       ├── service.py        # use cases
│       ├── models.py         # private
│       ├── repository.py     # private
│       └── internal/         # private
├── apps/desktop/
│   ├── src/main/             # Electron main
│   ├── src/preload/          # contextBridge surface
│   └── src/renderer/         # React; no Node, no database
├── tools/                    # the verification commands
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   ├── negative/             # fixtures that must fail a check
│   └── contracts/            # generated-contract drift
├── migrations/               # Alembic revisions; 0001 executes the baseline SQL
└── vendor/euro-office/       # fetch pins, never binaries in git
```

---

## 3. Module shape

- **Domain**: entities, value objects, invariants, policies. Pure Python, plain classes and
  dataclasses; Pydantic models belong at the boundaries, not in the domain. No FastAPI, SQLAlchemy,
  Pydantic AI, Electron, filesystem or network.
- **Application services**: use cases, transactions, authorisation, audit. Own the operation.
- **Infrastructure**: PostgreSQL repositories, blobs, browser, editor, model providers, court
  adapters. No business authority.
- **Interfaces**: FastAPI, Typer, Pydantic AI tools, Electron IPC. Thin adapters only.
- **Agent composition**: `AgentComposition` wires Harness capabilities and the legal pack to
  services through the gateway.
- **Root**: the only place infrastructure is constructed.

Documents have four distinct jobs: Euro-Office renders DOCX and PDF; `x2t` converts; the builder
writes; `lxml` reads the OOXML package for verification. The editor API is not a server-side parser.

Public per module: `api.py`, `contracts.py`, `service.py`. Everything else is private. The
table-ownership manifest names one owner per table.

---

## 4. Verification commands

One command, harness-neutral:

```bash
python -m tools.verify --fast     # seconds: lint, types, boundaries, docs, parity
python -m tools.verify --full     # adds unit, integration, E2E, negative, drift
python -m tools.verify --rule R2  # run one rule and its negative test
```

`tools/` contains:

| Tool | Rule |
|---|---|
| `verify.py` | orchestrator; fast and full |
| `markdown_policy.py` | approved files only, no `FINAL`/`V2`, no duplicates |
| `ownership.py` | every table has exactly one owner |
| `operations.py` | every operation has CLI, HTTP and tool surfaces, or a declared exception |
| `comments.py` | AST-aware comment ban with the allowed exceptions |
| `court_leak.py` | court names only in adapter data |
| `contracts_drift.py` | generated contracts match their source |
| `negative.py` | runs the fixtures that must fail |

CI runs `--full` on every pull request. Hooks are a convenience; they are never the gate.

---

## 5. Documents

- `docs/v1/` is the only design authority. Five documents and the SQL appendix.
- `docs/agents/` holds consumer rules for the engineering skills.
- `docs/implementation/` holds approved plans. It is not design authority and must not restate it.
- A new Markdown file is a deliberate act: add it to the policy allowlist and say why in the same
  change.
- No `FINAL`, `UPDATED`, `NEW` or `V2` names. Update the owner.

---

## 6. Build order

1. Scaffold the tree, `pyproject.toml`, `uv.lock`, `package.json`, `tools/verify.py` skeleton.
2. Add the boundary checks: import-linter, dependency-cruiser, renderer isolation.
3. Add the operation registry and the three surface adapters for one operation.
4. Add the type framework and the contract drift test.
5. Add the negative fixtures, one per rule.
6. Wire CI to `--full`; keep hooks optional.
7. Only then add the first real module.

---

## 7. Non-goals

- No second agent runtime, no second harness.
- No second application-service layer, registry or orchestrator.
- No generic framework; `tools/` is a small set of checks, not a platform.
- No implementation before approval of the enforcement plan.
