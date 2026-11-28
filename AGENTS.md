MavrykX is a self-hosted legal-work platform for one firm; Maverick is its one agent.

## Repository map

- `src/mavrykx/` — Python server.
- `apps/desktop/` — Electron and React.
- `src/mavrykx/modules/` — owning modules.
- `docs/` — design, plans, rules.
- `tools/` — checks.
- `tests/` — unit, integration and negative fixtures.
- `migrations/` — Alembic baseline.
- `vendor/euro-office/` — third-party adapter source; never product code.
- `.reference/` — local only; read only when asked.

## Commands

- `uv` for Python; `npm` for Node.
- Fast: `uv run python -m tools.verify --fast`; full: `uv run python -m tools.verify --full`.

## Working with the user

- Say your next action in one line; update every few tool calls. When complete, recap findings, actions and next step.
- Treat answered questions as done; revisit only if asked or wrong.
- Do not end while work remains, announce a next step without taking it, offer to wait, list non-blocking decisions (except Plan Mode), or report a milestone as finished. End only when blocked or complete; if blocked, say what blocks and unblocks. Confirm risky actions.
- Put status and recap with your next tool call.

## Writing

- Write for a smart reader: self-contained, key point first, plain words, short active sentences, one idea each, one word per thing. Do not invent terms.
- Use prose for connected ideas and bullets for separate items. Be concise; keep needed context.

## Rules

- Never add comments to code.
- If docs and code disagree, follow the code and report each mismatch.
- Match evidence to the change; do not default to the full suite.

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.
