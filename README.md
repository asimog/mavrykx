# MavrykX

**Architecture.** No application code yet. **MavrykX** is the platform; **Maverick** is the one agent.

Start here: [docs/v1/01-architecture.md](docs/v1/01-architecture.md).

| Doc | Contents |
|---|---|
| [Detailed architecture](docs/v1/01-architecture.md) | System shape, modules, stack, dependency enforcement, deployment, build order, acceptance |
| [Domain model](docs/v1/02-domain-model.md) | Definitions, entities, relationships, lifecycles, invariants, matter-intelligence plan |
| [Application, agent and data](docs/v1/03-application-agent-and-data.md) | Application services, gateway, Pydantic AI/Harness, workflows, CLI, data, documents, security, audit |
| [Shared workspaces and collaboration](docs/v1/04-shared-workspaces-and-collaboration.md) | Matter workspace, conversations, access, live editing, distributed execution, submissions |
| [Product experience](docs/v1/05-product-experience.md) | Navigation, Today, Matter workspace, classification setup, documents, browser, Research Studio, library, workflows, inbox, onboarding |

The SQL appendix remains at [docs/v1/schema/0001_core.sql](docs/v1/schema/0001_core.sql); it is not a sixth document.

**The whole system is the scope.** Do not build until the gate conditions in the architecture doc pass.
