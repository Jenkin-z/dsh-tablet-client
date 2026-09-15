# Documentation Synchronization Standard

## Directory Responsibilities

| Directory | Required content |
| --- | --- |
| `docs/design/` | Current module boundaries, contracts, data models, states, workflows, side effects, and verification |
| `docs/decisions/` | Accepted long-lived choices, context, consequences, and alternatives |
| `docs/standards/` | Mandatory repository-wide engineering practices |
| `docs/standards/technology/` | Reusable technology baselines whose applicability and commands must be verified in the target repository |
| `docs/migration/` | Breaking changes, compatibility, rollout, verification, and rollback |
| `docs/plans/` | Future or historical implementation work; never current-behavior authority |
| `docs/report/` | Dated evidence; never current-behavior authority |
| `docs/research/` | Optional external or exploratory inputs; never current-behavior authority |

Keep the repository root limited to stable entry documents and files required by tooling.

## State Labels

Distinguish at least: implemented, planned, deprecated, and validation pending. Never present a plan, proposal, mock, or historical report as a currently available capability.

## Index And Cleanup Rules

- Every directory under `docs/` has a `README.md` index. Keep links relative, valid, and limited to documents that actually exist.
- Keep `docs/project-index.md` current for module, data-table, backend, frontend, API, job, test, and related-file ownership. It is an inventory that links to authoritative sources, not a duplicate design document.
- After a requirement or task is fully implemented, run a scoped cleanup over only the affected documentation. Merge repeated explanations, remove stale claims, archive or delete completed plans after recording durable outcomes, and repair indexes.
- Preserve unique decisions, compatibility history, audit evidence, and rollback guidance. Do not delete material merely because it is old or short.
- If cleanup changes ownership or removes meaningful content, record the result in the task handoff or a dated report.

### Documentation Maintenance Subagent

At project initialization, offer a separate documentation-maintenance subagent to reduce cost and keep cleanup focused. After each completed requirement/task, invoke it with a narrow prompt containing the task summary, affected paths, and the governing `AGENTS.md`/docs rules. Select a lower-cost model explicitly when the host supports per-subagent model selection; otherwise state that the subagent inherits the parent model and cost cannot be reduced by configuration alone.

Use this prompt shape:

```text
You are the documentation-maintenance subagent for <project>. Review only these affected paths: <paths>.
Task completed: <short summary>.
Update the relevant docs indexes and docs/project-index.md from verified facts. Merge exact or clearly duplicate content, remove stale claims, and archive/delete completed plans only after preserving durable outcomes in the authoritative document. Repair local links. Do not change source code, product behavior, unrelated docs, or accepted decisions. Mark uncertain facts as awaiting evidence. Return a concise list of changed files, removed/merged content, and unresolved items.
```

The primary agent reviews the subagent diff, resolves semantic decisions the subagent cannot prove, and runs `python scripts/check_skill.py --target <project-path>` (or the project’s documented validator) before handoff.

## Synchronization Triggers

| Change | Update in the same task |
| --- | --- |
| Public interface, contract, data model, state, workflow, or module boundary | Relevant `docs/design/` document |
| Long-lived tradeoff or technology/product choice | New or updated ADR under `docs/decisions/` |
| Repository-wide mandatory practice | Relevant `docs/standards/` document |
| Technology choice, version, toolchain, or technology-specific gate | Relevant `docs/standards/technology/` profile plus an ADR when the choice is long-lived |
| Breaking behavior or compatibility requirement | `docs/migration/` and, when lasting, an ADR |
| Implementation of a planned item | Current design/decision/standard plus plan status |
| Acceptance, audit, or investigation | Dated file under `docs/report/` |

## Minimum Design Content

A topic design should state scope and non-goals, owner and source of truth, public contracts, invariants, data or state behavior, compatibility, concurrency or idempotency needs, cancellation/timeouts/recovery where relevant, failure boundaries, side effects, dependencies, and verification entry points.

## Self-Check

- [ ] `docs/README.md` local links resolve.
- [ ] Current behavior and implementation evidence agree.
- [ ] Plans and reports are clearly non-authoritative.
- [ ] Breaking changes include compatibility and rollback guidance.
- [ ] Sensitive values and unnecessary raw logs are absent.
- [ ] Every `docs/` directory has a `README.md` index and `docs/project-index.md` reflects verified ownership.
- [ ] Completed-scope cleanup removed or merged repeated/stale content without deleting unique decisions or evidence.
