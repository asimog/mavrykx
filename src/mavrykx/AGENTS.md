# MavrykX — Python server

- Domain is plain Python. Application services own use cases, transactions, authorisation and audit.
- Interfaces and tools are thin. The agent uses the one gateway; no direct database, filesystem or repository access.
- Service writes emit audit events. RLS backs service permissions; it does not replace them.
- Keep module boundaries. Read [architecture §6](../../docs/v1/01-architecture.md) and [application services](../../docs/v1/03-application-agent-and-data.md) before changing layers or contracts.
- Run focused tests for the changed module, then the affected integration test. Use `uv run pytest <path> -q`.
