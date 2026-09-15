# Prisma Development Standard

## Applicability

This profile applies where Prisma defines database models, migrations, generated clients, or query behavior. Verify the Prisma version, database provider, schema locations, migration workflow, deployment topology, and exact commands from the target repository.

## Schema And Generated Client

- Treat the accepted Prisma schema and migrations as authoritative for persisted structure. Keep application DTOs, validation, queries, generated client versions, and documentation synchronized.
- Regenerate the client through the repository's established command after schema or generator changes, and detect stale generated artifacts in CI when practical.
- Review relation ownership, optionality, defaults, enum changes, indexes, unique constraints, foreign keys, referential actions, and mapped names for compatibility and data impact.
- Avoid exposing persistence models directly as public API contracts when their lifecycle and compatibility requirements differ.

## Migration Safety

- Use the repository's accepted migration workflow. Do not substitute schema push or ad hoc database changes for reviewed production migrations.
- Validate both clean database creation and upgrade from representative existing data.
- Plan additive rollout, backfill, validation, constraint enforcement, application cutover, and cleanup in a safe order for breaking or large changes.
- Document backup, audit, lock/downtime expectations, irreversible operations, verification, and rollback or forward-fix boundaries.
- Never edit an already-applied migration silently; use a documented corrective migration or the repository's accepted recovery procedure.

## Queries, Transactions, And Consistency

- Select only required data for sensitive or high-volume paths and review N+1 behavior, pagination, ordering, and index support.
- Define transaction boundaries around invariants, not convenience. Keep external side effects outside database transactions or reconcile them explicitly.
- Make retried and asynchronous writes idempotent where duplicate execution is possible.
- Handle known Prisma errors through stable domain error mapping without leaking sensitive database details.

## Verification Gates

- Use configured schema validation, formatting, client generation, migration status/diff, tests, and database smoke checks as distinct gates.
- Test constraints, relations, defaults, nullability, concurrency, transaction rollback, representative existing-data upgrades, and application compatibility in proportion to risk.
- Record the database provider/version and environment used for migration evidence; an in-memory or substitute database does not prove production compatibility.
