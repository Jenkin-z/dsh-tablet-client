# TypeScript Development Standard

## Applicability

This profile applies wherever TypeScript is compiled, type-checked, generated, or used to define shared contracts. Verify the compiler version, `tsconfig` hierarchy, package manager, runtime targets, and exact commands from the target repository.

## Compiler And Type Safety

- Preserve or strengthen the repository's established strictness. Do not disable compiler checks globally to make a change pass.
- Prefer precise types, discriminated unions, generics, and narrowing over `any`, unchecked assertions, or duplicate handwritten shapes.
- Treat `unknown` as untrusted until narrowed. Keep `null`, `undefined`, optional fields, and partial states explicit.
- Use suppression directives only for a documented, narrow incompatibility with an owner and removal condition. Do not use blanket `@ts-ignore`, permissive casts, or configuration downgrades as fixes.
- Keep source, test, build, generated, browser, server, and package `tsconfig` responsibilities clear when the repository has multiple configurations.

## Runtime Boundaries And Contracts

- TypeScript types disappear at runtime. Validate network, storage, environment, user, model, plugin, and tool input with the repository's selected runtime validation mechanism.
- Keep schemas, generated types, DTOs, API clients, event payloads, persistence models, and parsers synchronized through one authoritative contract.
- Model state transitions and errors explicitly instead of encoding invalid states through loosely related booleans or optional fields.
- Keep public exports deliberate and avoid bypassing module boundaries through deep internal imports.

## Testing And Gates

- Treat type checking, build/transpilation, lint, formatting, unit tests, integration tests, generated-code freshness, and package checks as distinct gates when configured.
- Do not assume a successful build proves a dedicated type check, or that type checking proves runtime validation and behavior.
- Add type-level or compile-failure tests when the repository supports them and the contract itself is the behavior under test.
- Cover runtime validation failures, optional/nullable data, exhaustive branches, async errors, serialization, and generated contract drift in proportion to risk.
- Run exact commands on the final tree and report any compiler configuration or package scope not exercised.
