# Engineering Standards

`docs/standards/` contains mandatory repository-wide engineering rules. `AGENTS.md` is only an entry summary and does not override topic standards.

## Standards

- [Development standard](./development-standard.md)
- [Code quality standard](./code-quality.md)
- [Technology-specific standards](./technology/README.md)
- [Documentation synchronization](./docs-sync.md)

Technology profiles are generated as reusable baselines even when the initial repository is empty. Mark each profile applicable or not applicable after inspecting the real stack, and add exact commands or thresholds only when repository evidence supports them. Add further security, release, and code-style standards only after verification.

## Conflict Priority

1. Explicit user requirements for the current task
2. Safety, legal, compliance, and authorization boundaries
3. A more specific `AGENTS.md` governing the files being changed
4. Accepted ADRs under `docs/decisions/`
5. Mandatory standards in this directory
6. Current design and contracts under `docs/design/`
7. Plans, reports, and research as non-authoritative supporting material
