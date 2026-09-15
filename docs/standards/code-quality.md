# Code Quality Standard

This document defines the default quality gates for production code, tests, contracts, data changes, and delivery. Tailor it to the repository, but do not weaken it merely to obtain a passing result.

## Verified Gate Inventory

本项目（Flutter/Dart）已验证的质量门禁：

| Gate | 命令 | 状态 |
|------|------|------|
| 静态分析 | `flutter analyze` | ✅ 零警告 |
| 构建验证 | `flutter build apk --release` | ✅ 必须通过 |
| 格式化 | `dart format --set-exit-if-changed .` | ✅ 检查用 |
| 单元测试 | `flutter test` | ⚠️ 待补充测试用例 |

- 不要发明未验证的命令、工具、覆盖率阈值
- 在最终工作树上运行检查，变更前的结果是过期证据

## Design And Contract Gate

- Before adding cross-module behavior, define the owner, source of truth, public contract, invariants, lifecycle, idempotency or concurrency behavior, cancellation, timeout, retry/recovery, compatibility, and failure boundaries that apply.
- Update or add the authoritative contract before or with its implementations. Keep schemas, generated artifacts, shared types, DTOs, transport frames, clients/parsers, persistence models, and documentation synchronized.
- Prefer a stable extension point and conformance tests before adding a new provider, action, adapter, plugin, or protocol implementation.
- Keep current facts, target design, migration state, and historical plans distinct. Do not document an unshipped architecture as implemented.

## Test Gate

- For new behavior or a defect, start with a focused test that fails for the expected reason when usable automated test infrastructure exists.
- Before risky refactoring, add characterization tests around externally visible behavior, side effects, error mapping, and compatibility so equivalence can be demonstrated.
- Cover normal behavior and risk-proportional boundary, invalid-input, failure, concurrency, idempotency, cancellation, timeout, retry/recovery, and partial-success cases.
- Prefer tests of observable behavior and real boundaries. Use mocks only where isolation is necessary, and avoid tests that merely confirm mock configuration or duplicate implementation details.
- Do not delete, skip, weaken, broadly rewrite, or lower existing tests/thresholds to make a change pass unless the governing contract intentionally changed and the same task updates the rationale and authoritative sources.
- If no practical automated harness exists, create the smallest repeatable check available and report the limitation, risk, and follow-up explicitly; do not silently claim full verification.

## Structure And Reuse Gate

- Keep one shared implementation of the same execution lifecycle. Route variations through interfaces, registries, adapters, strategies, workers, or parsers rather than duplicated orchestration or business-specific branches in common code.
- Consolidate repeated state handling, validation, authorization, error mapping, retry/recovery, serialization, upload, caching, and UI behavior behind clear ownership.
- Require at least two real consumers or one stable protocol-level responsibility before introducing a shared abstraction.
- Prevent touched high-complexity modules from becoming less cohesive. Put new behavior behind a smaller boundary and avoid unrelated rewrites.
- Remove dead code and compatibility shims only after verifying callers, persisted data, configuration, migrations, and rollback needs.
- Reject new giant files and giant methods. Keep responsibilities cohesive and place new behavior behind smaller boundaries when touching an oversized unit.
- Keep backend implementation inside the owning business/database module directory; require a documented cross-module owner before adding shared code.
- Review readability and stability explicitly: names, control flow, error handling, side effects, testability, and regression risk must remain clear and predictable.

## Data And Migration Gate

- Validate schema or migration changes against both a clean state and representative existing data when the project supports persistence.
- Check constraints, indexes, foreign keys, defaults, backfills, audit needs, compatibility windows, deployment order, verification, and rollback boundaries as applicable.
- Keep durable facts in an authoritative store; do not make recovery depend solely on an in-memory cache, transient notification channel, or client state.
- Make multi-step writes, retries, and asynchronous delivery idempotent or explicitly reconcile unknown/partial outcomes.

## Guard Pass

Review the final diff in four passes:

1. **Production code:** boundaries, correctness, errors, resources, concurrency, idempotency, compatibility, and maintainability.
2. **Tests:** regression proof, failure paths, race/recovery cases, real adapters or boundaries, and resistance to false positives.
3. **Contracts and docs:** current facts, public interfaces, migrations, decisions, setup commands, and verification evidence stay synchronized.
4. **Security and architecture:** secrets, authorization, untrusted input, arbitrary execution, path/network boundaries, duplicated state machines, and ownership violations.

Classify findings consistently:

| Level | Meaning | Completion rule |
| --- | --- | --- |
| Blocker | May cause unauthorized access, data loss/corruption, duplicate or unsafe execution, secret exposure, or an irreconcilable architecture split | Must be resolved before completion |
| Required | Violates an accepted contract, mandatory standard, test gate, ownership boundary, or creates material duplication/fragility | Must be resolved before completion |
| Follow-up | Does not block current correctness and has a clear owner, scope, and reason for deferral | May be recorded with explicit follow-up |

Do not relabel Blocker or Required findings as follow-up merely to finish the task.

## Quality Ratchet

- New work must not reduce existing test strength, type/static checks, security controls, contract coverage, migration safety, observability, or recovery behavior without an explicit accepted change.
- Do not introduce new plaintext secrets, arbitrary execution surfaces, unchecked external boundaries, ownerless durable state, duplicated orchestration, or permanent temporary paths.
- When touching known high-complexity or high-duplication code, do not make those properties worse; keep or improve cohesion and boundaries.
- Temporary exceptions must state scope, reason, risk, compensating control, owner, expiry/removal condition, and follow-up location. Exceptions never bypass safety or authorization requirements.

## Verification Evidence

For handoff, report:

- changed behavior and affected contracts or data;
- exact commands/checks run on the final tree and their results;
- tests added or updated, including the regression or risk they prove;
- checks not run, with reason and impact;
- remaining Blocker, Required, or Follow-up findings;
- rollback or recovery notes when the change can affect production state or compatibility.
