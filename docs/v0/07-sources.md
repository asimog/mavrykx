# Maverick — Sources and prior art

**Status:** reference list · **Date:** 2026-11-26
Nothing here is a source of product requirements; it is evidence for a recommendation.

---

## 1. Primary technical documentation

| Source | Used for | Status |
|---|---|---|
| [Pydantic AI 2.75.0](https://pypi.org/project/pydantic-ai/) | Agent runtime, Python ≥ 3.11, typed tools | Verified |
| [Pydantic Validation](https://pydantic.dev/docs/validation/latest/get-started/) | Application contracts: models, JSON Schema, validators, settings, strict mode | Verified |
| [Pydantic AI Harness index](https://pydantic.dev/docs/ai/harness/) | The official capability library; 0.x version policy | Verified |
| Harness capability pages ([Skills](https://pydantic.dev/docs/ai/harness/skills/), [SubAgents](https://pydantic.dev/docs/ai/harness/subagents/), [Dynamic Workflow](https://pydantic.dev/docs/ai/harness/dynamic-workflow/), [Planning](https://pydantic.dev/docs/ai/harness/planning/), [Memory](https://pydantic.dev/docs/ai/harness/memory/), [Compaction](https://pydantic.dev/docs/ai/harness/compaction/), [Step Persistence](https://pydantic.dev/docs/ai/harness/step-persistence/), [Guardrails](https://pydantic.dev/docs/ai/harness/guardrails/), [Permissions](https://pydantic.dev/docs/ai/harness/permissions/), [Approval Reviewer](https://pydantic.dev/docs/ai/harness/approval-reviewer/), [Require Verification](https://pydantic.dev/docs/ai/harness/require-verification/), [Goal](https://pydantic.dev/docs/ai/harness/goal/)) | The capability map and the capabilities we deliberately do not use | Verified |
| [Pydantic Evals](https://pydantic.dev/docs/ai/evals/evals/) | Output and trajectory evals | Verified |
| [Durable execution](https://pydantic.dev/docs/ai/capabilities/durable_execution/overview/) | DBOS adapter | Verified |
| [AG-UI protocol](https://docs.ag-ui.com/) | The agent↔user interaction protocol: events, state, tools, interrupts | Verified |
| [Pydantic AI AG-UI adapter](https://pydantic.dev/docs/ai/integrations/ui/ag-ui/) | The first-party `AGUIAdapter`; server-managed history; tool-approval interrupts; `ag-ui-protocol >= 0.1.19` | Verified |
| [CopilotKit](https://docs.copilotkit.ai/) | The AG-UI client framework; runs without cloud Intelligence; requires a Node runtime — rejected as a framework (RD-41) | Verified |
| [DBOS Python guide](https://docs.dbos.dev/python/programming-guide) | Workflow/step/queue API, Postgres system database | Verified |
| [Model Context Protocol](https://modelcontextprotocol.io/) | The tool wire protocol for **external** integrations, used through the Harness's MCP capability; internal tools stay in-process typed contracts (RD-44) | Standard |
| [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) | Matter isolation | Standard |
| [pgvector](https://github.com/pgvector/pgvector) | Embeddings without a vector database | Standard |
| [SQLAlchemy async](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html) | Database access | Standard |
| [FastAPI](https://fastapi.tiangolo.com/) | HTTP API | Standard |
| [Electron](https://www.electronjs.org/docs/latest/) | Desktop shell | Standard |
| [React](https://react.dev/) | UI | Standard |
| [OpenTelemetry](https://opentelemetry.io/docs/) | Traces and metrics | Standard |

## 2. Legal-technology prior art

| Source | What it shows | Status |
|---|---|---|
| [Stella](https://github.com/stella/stella) and [workspace](https://stll.app/product/workspace/) | A legal workspace with matters, documents, DOCX editing, research and chat; a desktop bridge to Word; its self-hosted onboarding (setup token → first account = admin) and one-organisation model are adopted (FD-11, RD-42) | Verified; onboarding and member model adopted, the rest reference for clarity |
| [cLawyer](https://github.com/lawyered0/cLawyer) | Matter-bound conversations, hard clearance gates, citation-gated readiness, retrieval packets, capability permissions, encrypted backups. It states it is **experimental and not safe for production** | Verified; used for security patterns only |
| [Harvey / Mia Jia, "Add Capabilities, Not Agents"](https://www.miajia.dev/writing/agent-tool-bundles/) | An agent is a system prompt plus tool bundles; bundles multiply, agents do not; an eval gate per bundle | Verified; used for the bundle model |
| [advdsh workspace editor](https://github.com/asimog/advdsh) | A legal DOCX workspace with block anchors, expected text, leases, stale-target rejection, single-writer commit and fan-out merge; a managed builder sidecar (hidden Electron and headless Chromium both proven), x2t as a per-conversion child process, a sha-verified vendored frontend rebuilt from a manifest, a hosting assessment that rejects DocumentServer for a single-user editor, and legal analyzers with `SCC`/`AIR` citation shapes and `Exhibit`/`Annexure`/`Schedule` cross-reference checks; its recorded gaps (route auth unproven; `replace_paragraph` on already-tracked paragraphs) are adopted as acceptance tests | Verified; the reference implementation for the document control pattern and the RD-52 process boundaries |
| [euro-office-lite](https://github.com/delmarguillen/euro-office-lite) | A third-party lightweight local-only editor shell (Tauri webview ↔ sdkjs/web-apps ↔ `bridge.js` ↔ Rust ↔ x2t); advdsh vendors only its frontend build pipeline, patches and pinned submodule SHAs — **the Rust half is not used** | Reference; not a dependency |
| [AgenticOS](https://github.com/vstorm-co/agenticos) | A self-hosted agent platform on Pydantic AI + the Harness: projects as shared file containers with standing instructions, attributed live shared chat with presence, generic read/use/edit resource grants, hash-chained per-organisation audit, two-commit run path, NOTIFY-woken job queue, `uncertain` workflow attempts, run manifests; project file concurrency is last-write-wins — **no concurrent document editing** | Verified; reference patterns only (RD-44–53); not a dependency |
| [Clio help centre](https://help.clio.com/) — Manage Tasks, Grow Contacts and Matters, Clio Work (Vincent AI) | Task private visibility, document attachments that never change document permissions, reminders, one-step task lists; the opportunity that converts to a matter carrying its record; matter/user/conversation memory and chat answers saved as documents. **Billing, estimates and invoicing surfaces are refused** (05 §4) | Verified; product-behaviour reference only |
| [OpenAdvo v2 blueprint](https://github.com/asimog/openadvo) | The post-mortem of a legal-agent architecture that failed on unowned concepts, unenforced claims, acception without gates; its doctrine, its failure register (FF-01…FF-34) and its editor mechanism (ADR-46: plugin-by-URL, checksummed tree, spike-gated patching). **Its stack decisions (SQLite per matter, Eve/TypeScript, DeepAgents rejected, Astryx, CLI-first) are a different product's frozen answers and are rejected here; its lessons and failure evidence are adopted** (VD-20) | Verified; the lessons adopted as RD-53, RD-54, RD-55, RD-57, RD-61, RK-20 and the RD-17 vendoring mechanism; the stack rejected |

## 3. Legal-research and filing sources

| Source | What it shows | Status |
|---|---|---|
| [Indian Kanoon API](https://api.indiankanoon.org/documentation/) | Paid case-law search API; an adapter candidate | Verified |
| [eCourts e-filing manual](https://districts.ecourts.gov.in/sites/default/files/efiling%20user-manual_1.pdf) | Filing steps and format requirements; a reference for rule data | Verified |
| Supreme Court of India — rules, practice directions, e-filing specs | The reference pack's apex-court instruments (FD-16) | To be verified per instrument; fetched and snapshot-hashed before use |
| Delhi High Court — Original and Appellate Side rules, practice directions, e-filing manual | The reference pack's primary target (OQ-1: one civil matter in the Delhi High Court) | To be verified per instrument |
| Delhi district courts — rules and eCourts filing manuals | The reference pack's district tier | To be verified per instrument |
| Official court and tribunal websites | Rules, practice directions, cause lists, orders | To be verified per forum; never assumed |

## 4. Remote-access prior art

| Source | What it shows | Status |
|---|---|---|
| [WireGuard](https://www.wireguard.com/) | Modern VPN; strong, but a client and key management | Standard |
| [Tailscale](https://tailscale.com/kb/1151/what-is-tailscale) | Mesh VPN with coordination; convenient but an external account | Standard |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Outbound-only reverse tunnel; TLS terminates at Cloudflare | Standard |
| [RFC 8656 (TURN)](https://datatracker.ietf.org/doc/html/rfc8656) | Relay for NAT traversal; ciphertext-only if E2E | Standard |
| [RFC 8445 (ICE)](https://datatracker.ietf.org/doc/html/rfc8445) | Direct connection negotiation | Standard |

## 5. Document and OCR tooling

| Source | Used for | Status |
|---|---|---|
| [Euro-Office](https://github.com/Euro-Office/DesktopEditors) — a fork of ONLYOFFICE carrying the whole **Docs** map: [web-apps](https://github.com/Euro-Office/web-apps) (the editor shell around sdkjs), [sdkjs](https://github.com/Euro-Office/sdkjs), [core](https://github.com/Euro-Office/core) (x2t), [DocumentServer](https://github.com/Euro-Office/DocumentServer) (Docker packaging), [server](https://github.com/Euro-Office/server) (co-editing source), [document-server-integration](https://github.com/Euro-Office/document-server-integration) (Apache-2.0 host glue) and connectors ([eurooffice-nextcloud](https://github.com/Euro-Office/eurooffice-nextcloud), Odoo). **No platform is forked** — the host always provides the collaboration layer | Maverick uses the editor and x2t, **not** the co-editing server (RD-49; [04-data-documents-security.md](04-data-documents-security.md) §2.5) | Vendor; **AGPL-3.0 on engine/shell/server; `DesktopEditors` carries a custom non-SPDX licence — professional licence review mandatory before distribution** |
| [Euro-Office/eurooffice-nextcloud](https://github.com/Euro-Office/eurooffice-nextcloud) | The Nextcloud connector (PHP, AGPL-3.0, apps.nextcloud.com/apps/eurooffice) that embeds the Euro-Office document server — the *host* provides the collaboration layer. Confirms the connector pattern; **rejected as a Maverick platform path**: Nextcloud as host means an external canonical store (04 §2.6) | Vendor; reference for the RD-49 upgrade path only |
| [ONLYOFFICE/CommunityServer](https://github.com/ONLYOFFICE/CommunityServer) | The upstream C# collaboration platform (DMS, projects, CRM, mail) - sometimes mistaken for part of the Euro-Office stack | Reference; **rejected**: a sixth runtime and a second product with its own authority model; no legal domain, no matter isolation |
| [python-docx](https://python-docx.readthedocs.io/) | DOCX parsing and inspection - read/verify only (RD-52) | Standard |
| [docxtpl](https://docxtpl.readthedocs.io/) | Template variables for non-legal boilerplate | Reference; not a legal-document mutation path - the builder is the sole mutator (RD-52) |
| [PyMuPDF](https://pymupdf.readthedocs.io/) | PDF text, page and render operations | Standard |
| [OCRmyPDF](https://ocrmypdf.readthedocs.io/) | OCR for scanned PDFs | Standard |
| [docTR](https://github.com/mindee/doctr) | Optional second OCR engine | Standard |
| [LibreOffice](https://www.libreoffice.org/) | Headless PDF/PDF-A fallback | Standard |
| [Playwright](https://playwright.dev/python/) | Browser automation in a worker — portal access and the headless-Chromium family for the builder host | Standard |

## 6. How to read the status column

| Status | Meaning |
|---|---|
| **Verified** | Read or measured against the source; the claim is supported |
| **Standard** | Stable, well-known documentation; not re-fetched |
| **Vendor** | A vendor source; behaviour and licence must be verified before distribution |
| **Reference** | Prior art; used for ideas, not copied as a dependency |
| **To be verified** | A source the firm must check for the relevant forum and date |

---

*Back to [00-README.md](00-README.md).*
