# Python Development Standard

## Applicability

This profile applies to Python source, packages, scripts, services, workers, tests, and automation. Verify the supported Python versions, environment manager, dependency source, and exact commands from the target repository before treating tool examples as mandatory.

## Runtime And Dependencies

- Declare supported Python versions in the repository's authoritative configuration and keep local, CI, packaging, and production runtimes aligned.
- Use an isolated environment and the repository's chosen dependency/lock mechanism. Do not mix global packages into verification evidence.
- Keep runtime and development dependencies intentional; remove or upgrade dependencies only after checking imports, plugins, generated artifacts, packaging, and deployment consumers.
- Prefer module execution through the selected environment so imports and entry points resolve consistently.

## Types, Interfaces, And Errors

- Type public boundaries and shared data models where the project uses static typing. Keep annotations synchronized with runtime behavior.
- Validate external data at runtime; type annotations alone do not validate network, file, environment, model, or tool input.
- Raise or return domain-appropriate errors with preserved causes. Avoid broad exception swallowing and catch only where recovery, translation, cleanup, or context is added.
- Keep import direction and package boundaries explicit. Avoid circular imports, hidden path mutation, and reliance on the current working directory.

## Resources, Concurrency, And Safety

- Use context managers or equivalent cleanup for files, locks, transactions, network clients, temporary resources, and subprocesses.
- Define timeouts, cancellation, retry limits, and partial-failure behavior for asynchronous, threaded, multiprocessing, or remote work.
- Launch subprocesses with argument arrays, controlled executables and working directories, bounded output, and `shell=False` unless shell evaluation is an explicit reviewed requirement.
- Treat dynamic imports, `eval`/`exec`, pickle-like deserialization, YAML loaders, archive extraction, and filesystem paths as security-sensitive boundaries.

## Testing And Gates

- Use the test runner already selected by the repository, such as `pytest` or `unittest`; do not introduce or assume one without evidence.
- Consider configured type tools such as mypy or Pyright, lint/format tools such as Ruff, Flake8, or Black, packaging checks, and syntax/import compilation as distinct gates.
- Add focused regression tests for defects and behavior changes. Test exceptions, cleanup, encoding, path handling, concurrency, and version-sensitive behavior in proportion to risk.
- Run the exact repository commands on the final environment and report the interpreter version and unavailable gates.
