# MavrykX — Desktop

- Renderer uses React and the preload API only. No Node, database, filesystem or secrets.
- Main owns OS integration and the device key; it owns no legal record.
- Keep preload narrow. Add a typed method instead of exposing Node.
- Commands: `npm run typecheck`, `npm run lint`, `npm test`, `npm run build`.
- Use `npx vitest run <file>` for a focused test. Use Playwright only for Electron flows.
- Read [architecture §6](../../docs/v1/01-architecture.md) and [collaboration §6](../../docs/v1/04-shared-workspaces-and-collaboration.md) before changing IPC or the editor.
