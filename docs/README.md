# dsh-tablet-client - Documentation Map

`docs/` separates current design and binding decisions from plans and point-in-time evidence.

| Directory | Role | Authority |
| --- | --- | --- |
| [design/](./design/) | Current architecture, module boundaries, contracts, states, and workflows | Current design authority |
| [decisions/](./decisions/) | Accepted long-lived choices and consequences (ADR) | Binding decisions |
| [migration/](./migration/) | Breaking changes, compatibility, rollout, and rollback | Change-specific authority |
| [plans/](./plans/) | Future or historical implementation plans | Non-authoritative |
| [report/](./report/) | Dated tests, audits, acceptance, and investigations | Point-in-time evidence |
| [standards/](./standards/) | Mandatory repository engineering and documentation rules | Binding standards |


## Entry Points

- [Project overview](../README.md)
- [Agent and development rules](../AGENTS.md)
- [Project implementation index](./project-index.md)
- [Standards and conflict priority](./standards/README.md)
- [Development standard](./standards/development-standard.md)
- [Code quality standard](./standards/code-quality.md)
- [Technology-specific standards](./standards/technology/README.md)
- [Documentation synchronization rules](./standards/docs-sync.md)

Every `docs/` subdirectory has its own `README.md` index. Add links to real topic documents here as they are created. Do not index planned files as if they already exist.
