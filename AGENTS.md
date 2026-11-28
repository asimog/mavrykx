MavrykX is a self-hosted legal-work platform for one firm; Maverick is its one agent.

## Repository map

- `src/mavrykx/` — Python server: domain, application services, interfaces, gateway, agent, composition and root.
- `apps/desktop/` — Electron main, preload and React renderer.
- `modules/` — one package per owning module; the module map is in [01-architecture](docs/v1/01-architecture.md).
- `docs/v1/` — design authority: [architecture](docs/v1/01-architecture.md), [domain model](docs/v1/02-domain-model.md), [application/agent/data](docs/v1/03-application-agent-and-data.md), [collaboration](docs/v1/04-shared-workspaces-and-collaboration.md), [product experience](docs/v1/05-product-experience.md) and the [SQL schema](docs/v1/schema/0001_core.sql).
- `docs/implementation/` — [scaffold and pins](docs/implementation/repo-scaffold.md), [enforcement](docs/implementation/enforcement-audit-plan.md) and the Euro-Office plans.
- `docs/agents/` — [issue tracker](docs/agents/issue-tracker.md) and [domain-doc rules](docs/agents/domain.md).
- `tools/` — `tools.verify` and its checks.
- `tests/` — unit, integration and negative fixtures.
- `migrations/` — Alembic baseline.
- `vendor/euro-office/` — [PostgreSQL queue adapter](vendor/euro-office/pg-adapter/README.md).
- `references/` — [Kosmos and Stella study](references/README.md).

## Commands

- `uv` manages Python; `npm` manages Node.
- Fast: `uv run python -m tools.verify --fast`
- Full: `uv run python -m tools.verify --full` — prerequisites are in [repo-scaffold](docs/implementation/repo-scaffold.md).

Design decisions live in `docs/v1/`; pins, checks and plans live in `docs/implementation/`. Update the owning document, not this file.

## Working with the user

- Say your next action in one line. Update every few tool calls.
- When work is complete, end with a standalone recap: findings, actions, next step.
- Treat answered questions as done. Focus on the new request; revisit old answers only if asked or wrong.

## Turns

- A message with no tool call ends the turn. Do not end while work remains.
- Do not announce a next step without taking it, offer to wait, list non-blocking decisions unless asked, or report a milestone as finished. Put status notes and the recap with your next tool call.
- End only when blocked or complete; if blocked, say what blocks it and what would unblock it. Confirm risky or destructive actions first.

## Writing

- Write for a smart reader. Make messages self-contained; key point first.
- Use plain words, short active sentences, one idea each. Use one word per thing; do not invent terms.
- Use prose for connected ideas, bullets for separate items. Be concise; keep needed context.

## Living documentation

- Update this file in the same pull request when the map or a process changes. Review it in code review, keep it aligned with `README.md`, and audit quarterly.
- Link to the owning document; do not copy it. Outdated instructions are worse than none.

## Working rules

- If `AGENTS.md` and the code disagree, follow the code and report each mismatch in your final reply.

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.
