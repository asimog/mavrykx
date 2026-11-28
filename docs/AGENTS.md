# MavrykX — Documentation

- `docs/v1/` is design authority: [architecture](v1/01-architecture.md), [domain model](v1/02-domain-model.md), [application/agent/data](v1/03-application-agent-and-data.md), [collaboration](v1/04-shared-workspaces-and-collaboration.md), [product experience](v1/05-product-experience.md) and the [SQL schema](v1/schema/0001_core.sql).
- `docs/implementation/` holds [pins and scaffold](implementation/repo-scaffold.md), [enforcement](implementation/enforcement-audit-plan.md) and the Euro-Office plans.
- Every truth has one owner. Link to the owner; do not copy it.
- Update the owner and root `README.md` in the same change. Add new Markdown to `tools/markdown_allowlist.toml`.
- House style: `# MavrykX — <name>`, status/version/date, terse declarative prose, British spelling, mermaid for diagrams.
- Docs check: `uv run python -m tools.markdown_policy`. Run the link check before hand-off.
