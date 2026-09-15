# Node.js Development Standard

## Applicability

This profile applies to software executed by Node.js, whether written in JavaScript, TypeScript, or generated code. Verify the supported Node.js versions, package manager, lockfile, module format, process model, and exact commands from the target repository.

## Runtime And Dependencies

- Keep local, CI, build, and production Node.js versions aligned through the repository's established version declaration.
- Use the package manager matching the committed lockfile. Do not regenerate or replace lockfiles casually.
- Review dependency changes for runtime compatibility, install scripts, native modules, licensing, security advisories, bundle impact, and transitive churn.
- Keep CommonJS/ES module boundaries and package exports explicit. Avoid relying on undeclared globals or environment-specific resolution.

## Async And Process Lifecycle

- Await or return every promise whose completion matters. Handle rejected promises at an ownership boundary and preserve error causes.
- Define timeouts, cancellation, retry limits, and idempotency for network, queue, filesystem, subprocess, and external-service operations.
- Close servers, sockets, streams, timers, workers, file handles, database clients, and subscriptions on success, failure, cancellation, and shutdown.
- Handle process signals and graceful shutdown according to the deployment model. Do not treat process exit as successful before durable work is committed or reconciled.
- Respect stream backpressure and output limits; do not buffer unbounded request bodies, logs, artifacts, or child-process output.

## Input And Execution Safety

- Validate environment variables and external input before use. Keep secrets out of source, logs, error payloads, fixtures, and client bundles.
- Launch child processes with argument arrays, fixed executables, controlled working directories, timeouts, and bounded output. Avoid `shell: true` for untrusted or variable input.
- Normalize and authorize file paths, URLs, redirects, archive entries, and network destinations at trust boundaries.

## Testing And Gates

- Treat tests, type/static checks, lint, formatting, build, package validation, dependency audit, and runtime smoke checks as distinct gates when configured.
- Cover async rejection, timeout, cancellation, duplicate delivery, graceful shutdown, resource cleanup, stream behavior, and version/module-format compatibility in proportion to risk.
- Run commands with the repository's package manager on the final tree and report the Node.js version and workspace/package scope exercised.
