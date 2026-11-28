# MavrykX — Euro-Office runtime package

**Status:** proposal · **Version:** 9.3.8 · **Date:** 2026-11-28

Measured analysis of Euro-Office 9.3.8 reduced to the smallest reliable set for Word,
Spreadsheet, PDF, DOCX/XLSX/PDF conversion and font discovery. The DocumentServer measurements
are retained for the deferred shared-session option; V1 runs the local editor and `x2t` only.
No presentation support.

Every number below is measured from the published 9.3.8 assets, not estimated. Sizes are MiB.

---

## 1. Source verification

| Item | Value |
|---|---|
| DesktopEditors tag | `v9.3.8`, commit `e681296d8173` |
| Asset | `Euro-Office-DesktopEditors-9.3.8-0-windows-x64.zip` |
| Asset size | 735.9 MB compressed, 1,726.9 MB extracted, 18,717 files |
| SHA-256 | `abb6c881cd3ecc8e4bb4bb32e8b633dd11baf95bb285804ac318773959bd7a55` — matches the release digest |
| DocumentServer tag | `v9.3.8` |
| Asset | `euro-office-documentserver_9.3.8-0_amd64.deb` |
| Asset size | 433.6 MB compressed, 1,945.5 MB extracted, 19,692 files |
| OpenAdvo package | `vendor.lock.json` pins **v9.3.6** (`8b25e8a`), not 9.3.8 |

**OpenAdvo cannot supply the 9.3.8 files.** Its lock file names
`Euro-Office-DesktopEditors-9.3.6-0-windows-x64.zip` and commit `8b25e8a`. The
1,392.5 MB package under `resources/euro-office/win-x64` is one release behind and
must be replaced, not reused.

**Licence.** The DocumentServer ships `LICENSE` = **GNU AGPL-3.0**. The DesktopEditors
zip carries no `LICENSE` file at its root; upstream Euro-Office is the same AGPL-3.0
project, so the obligation is the same, but the notice must be added before
redistribution. Vendoring the binaries into a public repository is distribution and
triggers the AGPL's source and notice obligations for the combined work. This is a
product decision, not a packaging detail; it is recorded here rather than assumed.

---

## A. Directory size report

### DesktopEditors

| Scope | Size | Files |
|---|---:|---:|
| Full extracted install | 1,726.9 MB | 18,717 |
| Desktop shell (`DesktopEditors.exe`, Qt, codecs, CEF) | 695.6 MB | — |
| Four-directory runtime (`editors`, `converter`, `dictionaries`, `fonts`) | 1,031.3 MB | 18,329 |
| **Proposed minimal runtime** | **345.9 MB** | **3,739** |

The shell is the full desktop application. MavrykX embeds the editor in Electron and
needs none of it; OpenAdvo already excludes it, which is why its package is 1.39 GB
rather than 1.73 GB.

### DocumentServer

| Scope | Size | Files |
|---|---:|---:|
| Extracted package | 1,931.4 MB | 19,628 |
| **Proposed minimal runtime** | **1,163.7 MB** | **4,270** |

### Combined

| | Full | Proposed | Saved |
|---|---:|---:|---:|
| Desktop runtime | 1,031.3 MB | 345.9 MB | 66.5% |
| DocumentServer | 1,931.4 MB | 1,163.7 MB | 39.7% |
| **Total** | **2,962.7 MB** | **1,509.6 MB** | **49.0%** |

The DocumentServer floor is set by two monolithic binaries: `server/DocService/docservice`
(287.8 MB) and `server/FileConverter/converter` (236.1 MB). They cannot be pruned from
outside; only the assets beside them can.

---

## B. File inventory

Grouped by retained runtime. Locales and help pages are counted inside their editor, so
the groups sum to the full 1,031.3 MB desktop runtime.

| Group | Full | Retained | Files (full) |
|---|---:|---:|---:|
| Word (`apps/documenteditor`, `sdkjs/word`, EN document templates) | 82.0 MB | 36.9 MB | 3,173 |
| Spreadsheet (`apps/spreadsheeteditor`, `sdkjs/cell`) | 139.2 MB | 42.1 MB | 10,951 |
| PDF (`apps/pdfeditor`, `sdkjs/pdf`) | 64.6 MB | 46.7 MB | 487 |
| Presentation (`apps/presentationeditor`, `sdkjs/slide`) | 86.9 MB | 0 | 1,867 |
| Visio (`apps/visioeditor`, `sdkjs/visio`) | 23.3 MB | 0 | 188 |
| Shared SDK (`sdkjs/common`) | 31.9 MB | 31.9 MB | 375 |
| Shared web-apps (`apps/common`, `apps/api`) | 2.2 MB | 1.6 MB | 222 |
| Shared vendor (`web-apps/vendor`) | 23.3 MB | 23.3 MB | 208 |
| Converter (`converter/`) | 333.7 MB | 140.3 MB | 553 |
| Fonts (`fonts/`) | 4.9 MB | 4.9 MB | 21 |
| Dictionaries (`dictionaries/`) | 239.3 MB | 18.1 MB | 346 |
| Other (`webext`, `sdkjs/develop`) | 0.2 MB | 0.1 MB | 6 |

DocumentServer retained inventory:

| Group | Full | Retained |
|---|---:|---:|
| Server (`DocService`, `FileConverter`, `schema`, `tools`) | 784.4 MB | 784.4 MB |
| Core fonts (`core-fonts/`) | 156.7 MB | 156.7 MB |
| SDKJS | 149.1 MB | 111.1 MB |
| Web apps | 333.4 MB | 93.2 MB |
| Dictionaries | 239.3 MB | 18.1 MB |
| Document templates | 4.2 MB | 0.1 MB |
| Admin panel | 143.8 MB | 0 |
| Metrics | 71.3 MB | 0 |
| npm registry snapshot | 49.1 MB | 0 |

---

## C. Dependency report

Evidence is the loader configuration and bundle presence, not assumption.

| Retained editor | SDK bundle | Shared assets it loads |
|---|---|---|
| Word | `sdkjs/word/sdk-all-min.js` (2.5 MB) | `sdkjs/common` (fonts, spell, charts, zlib, hash, native), `web-apps/vendor`, `apps/common`, `apps/api`, `fonts`, `dictionaries`, `converter/AllFonts.js` |
| Spreadsheet | `sdkjs/cell/sdk-all-min.js` (2.2 MB) | same shared set, plus `resources/formula-lang/en*.json` |
| PDF | `sdkjs/pdf/` engine (`drawingfile.wasm` 12.2 MB, `cmap.bin` 9 MB) | `sdkjs/common`, `web-apps/vendor`, `apps/api` |
| Converter | `converter/x2t.exe` → `x2tlib.dll` | `DoctRenderer.config` names `../editors/sdkjs`, `../dictionaries`, `../editors/sdkjs/common/Native/*.js`, `web-apps/vendor/xregexp` |
| DocumentServer | `server/DocService/docservice`, `server/FileConverter/converter` | `web-apps`, `sdkjs`, `core-fonts`, `dictionaries`, `document-templates/new/en-US`, `fonts` |

Each editor app's `app.js` names `sdk-all-min`, matching the per-module bundle. The
presentation and Visio apps are the only referrers of `sdkjs/slide` and `sdkjs/visio`;
nothing in the Word, Spreadsheet or PDF bundle names them. That is the basis for
removing both.

`converter/DoctRenderer.config` shows the converter needs the `sdkjs` tree and the
dictionary tree at runtime — so `sdkjs/common` is not removable even if no editor were
open, and `dictionaries` cannot be dropped wholesale.

---

## D. Proposed runtime allowlist

```
editors/sdkjs/common/**
editors/sdkjs/word/**
editors/sdkjs/cell/**
editors/sdkjs/pdf/**
editors/sdkjs/vendor/**
editors/web-apps/vendor/**
editors/web-apps/apps/api/**
editors/web-apps/apps/common/**
editors/web-apps/apps/documenteditor/**            except main/locale/*.json != en.json
                                                   except main/resources/help/{de,es,fr,it,pt,ru,tr}/**
editors/web-apps/apps/spreadsheeteditor/**         except main/locale/*.json != en.json
                                                   except main/resources/help/{de,es,fr,it,pt,ru,tr}/**
                                                   except main/resources/formula-lang/* != en*
editors/web-apps/apps/pdfeditor/**                 except main/locale/*.json != en.json
                                                   except main/resources/help/{de,fr,pt,ru}/**
editors/webext/**                                  (single 0.1 MB file, purpose unverified)
converter/**                                       except templates/* != EN
                                                   except templates/EN/Presentation/**
                                                   except empty/* not in {en-GB, en-US, default}
dictionaries/en_**/**
fonts/**
```

DocumentServer allowlist:

```
server/DocService/**
server/FileConverter/**
server/schema/**
server/tools/**
web-apps/apps/{api,common,documenteditor,spreadsheeteditor,pdfeditor}/**
web-apps/vendor/**
sdkjs/{common,word,cell,pdf,vendor}/**
core-fonts/**
dictionaries/en_**/**
document-templates/new/en-US/**
LICENSE, LICENSE.txt, LICENSE-CC.txt, NOTICE, 3rd-Party.txt
```

---

## E. Removal list with evidence

| Removed | Size | Evidence |
|---|---:|---|
| `apps/presentationeditor` + `sdkjs/slide` | 86.9 MB | Presentation support not required; only the presentation app references the slide bundle |
| `apps/visioeditor` + `sdkjs/visio` | 23.3 MB | No requirement covers Visio; only the Visio app references the bundle |
| Non-English dictionaries (41 language dirs; keep `en_AU`, `en_CA`, `en_GB`, `en_US`, `en_ZA`) | 221.2 MB | English-only requirement; Hunspell dictionaries are selected by locale |
| Non-English document templates (`converter/templates/{AR,DE,ES,FR,IT,JA,PT,RU,ZH}`) | 188.4 MB | Template selection is per language; `EN` retained |
| Non-English help (`de, es, fr, it, pt, ru, tr` across retained editors) | 110.5 MB | Help is static per-language `.htm`; English retained |
| Non-English UI locales (44 of 45 JSON packs per editor) | 43.3 MB | `en.json` retained; the rest are separate files loaded on demand |
| `converter/templates/EN/Presentation` | 2.8 MB | Presentation removed |
| Non-English empty templates (42 locale dirs) | 2.2 MB | `en-GB`, `en-US`, `default` retained |
| Non-English formula names | 6.8 MB | `en.json`, `en_desc.json` retained |
| DocumentServer: presentation + slide | 83.6 MB | Same as desktop |
| DocumentServer: Visio + visio SDK | 30.4 MB | Same as desktop |
| DocumentServer: non-English dictionaries | 221.2 MB | Same as desktop |
| DocumentServer: non-English help | 110.5 MB | Same as desktop |
| DocumentServer: non-English UI locales | 46.7 MB | Same as desktop |
| DocumentServer: non-English new templates | 2.4 MB | `en-US` retained |
| DocumentServer: sample templates | 1.8 MB | Samples are not runtime |
| DocumentServer: `server/AdminPanel` | 143.8 MB | Separate web admin UI; MavrykX exposes its own settings surface |
| DocumentServer: `server/Metrics` | 71.3 MB | Monitoring service; not used by the product |
| DocumentServer: `npm/json` | 49.1 MB | Registry snapshot used by the plugin installer; no plugin install path is planned |
| Desktop shell (`DesktopEditors.exe`, Qt, CEF, codecs) | 695.6 MB | MavrykX embeds the editor in Electron; the shell is never launched |

The last five items are the only removals that are not purely language pruning. Each is
recorded with its reason so a reviewer can reverse a single line.

---

## F. Test plan

The reduced package passes only when every check below passes on the reduced tree.

| # | Check | Method | Pass |
|---|---|---|---|
| 1 | Open and edit DOCX | Editor host, open a fixture, insert text, save | Document opens; edit persists |
| 2 | Preserve styles, tables, numbering, headers | Byte-level compare after a no-op round trip | No structural loss |
| 3 | Save and reopen DOCX | Save, reopen in the same host and in Word/LibreOffice | Both render identically |
| 4 | Open and edit XLSX | Open fixture, edit a cell, save | Edit persists |
| 5 | Preserve formulas, formatting, multiple sheets | Round-trip compare | Formulas and sheets intact |
| 6 | Save and reopen XLSX | Reopen in host and Excel/LibreOffice | Values and formulas correct |
| 7 | Open and view PDF | PDF editor on a text PDF | Pages render |
| 8 | Verify PDF text and page rendering | Extract text and compare page count | Text matches fixture; page count matches |
| 9 | Generate and load the font list | Call the font-list path; confirm `AllFonts` output | Expected families present, no missing-font errors |
| 10 | Convert DOCX → PDF and XLSX → PDF via `x2t` | Run `x2t` from the reduced `converter/` | Output opens; text and layout preserved |
| 11 | Existing editor-host tests | Run OpenAdvo's editor-host suite against the reduced tree | Same pass/fail as the full tree |

Add two guard checks: no request for a removed locale or help path returns 404 during
normal use, and the DocumentServer starts and opens one co-editing session with the
reduced `web-apps`/`sdkjs` tree.

---

## Determinations

**1. Languages removable.** Keep English only.

| Class | Total | Keep | Remove |
|---|---:|---:|---:|
| UI locales (JSON per editor) | 45 | `en.json` | 44 |
| Help languages | 9 incl. `images` | `en`, `images` | 8 |
| Hunspell dictionaries | 46 | 5 English | 41 |
| Document templates | 10 | `EN` | 9 |
| Empty templates | 45 | `en-GB`, `en-US`, `default` | 42 |
| Formula names | 36 | `en`, `en_desc` | 34 |
| DocumentServer new templates | 45 | `en-US` | 44 |

Fonts are **not** a language class. `core-fonts` carries Indic and Latin families
(Lohit, Samyak, DejaVu, Liberation, Noto) that Indian legal documents need. CJK, Tibetan,
Khmer and Thai families total roughly 110 MB and are removable only as a product
decision, not as language pruning; they stay in the allowlist until that decision is made.

**2. Minimum required files and dependencies.** 345.9 MB desktop (3,739 files) plus
1,163.7 MB DocumentServer (4,270 files). The desktop floor is the three editors and their
SDK bundles — Word 36.9 MB, Spreadsheet 42.1 MB, PDF 46.7 MB — plus `sdkjs/common`
31.9 MB, `web-apps/vendor` 23.3 MB, the converter 140.3 MB, English dictionaries 18.1 MB
and fonts 4.9 MB.

**3. Safe removal candidates.** Everything in section E except the five non-language
items — those are evidenced but need a runtime confirmation.

**4. Unverified dependencies.**

- `sdkjs/common` contains chart and SmartArt code that may reference slide-only symbols.
  Removal of `slide` is proven by path, not by executing every shared code path.
- Whether `x2t` loads `sdkjs/slide` at startup for any conversion, independent of the
  presentation editor.
- `editors/webext` — one 0.1 MB file of unknown purpose; kept to be safe.
- Two `AllFonts.js` copies exist (`converter/` and `editors/sdkjs/common/`); which one
  the font-list path reads is not proven.
- `converter/templates/EN/Forms` (11 MB) is retained although forms support is not in the
  requirement list.
- `server/npm/json` removal assumes no server-side plugin installation.
- `core-fonts` trimming assumes no CJK/Tibetan/Khmer/Thai content in legal documents.

**5. Expected size reduction.** Desktop 1,031.3 → 345.9 MB (−66.5%); DocumentServer
1,931.4 → 1,163.7 MB (−39.7%); combined 2,962.7 → 1,509.6 MB (−49.0%). Trimming CJK
fonts would take the DocumentServer to roughly 1,054 MB.

---

## Packaging notes

- **Case collision.** The DocumentServer deb contains both `LICENSE` (file) and `license/`
  (directory). They cannot coexist on a case-insensitive filesystem; extracting on Windows
  loses the directory. Consume the deb on Linux, or rename one entry in the extraction
  script. This is why the DocumentServer should stay a Linux artifact.
- **Do not commit the binaries to the public repository.** Two packages plus Git history
  is roughly 3 GB, and the AGPL applies to distribution. The recommended shape is a
  pinned `vendor.lock.json` plus a fetch-and-verify script, with the extracted tree
  git-ignored — the same contract OpenAdvo already uses, without its in-repo payload.
- **Verification.** Both downloads were checked against the release SHA-256 before
  extraction. Re-verify on every fetch; a changed digest is a failure, not a warning.
