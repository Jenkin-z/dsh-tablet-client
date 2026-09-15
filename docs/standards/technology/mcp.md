# MCP Development Standard

## Applicability

This profile applies to Model Context Protocol clients, servers, tools, resources, prompts, transports, and host integrations. Verify the SDK/version, transport, host permissions, authentication model, and exact test commands from the target repository.

## Tool And Protocol Contracts

- Give each tool a stable, purpose-specific name, documented input Schema, structured result, bounded side effects, timeout behavior, and consistent error model.
- Treat tool descriptions and schemas as public contracts. Version or migrate breaking changes instead of silently changing accepted inputs or result shapes.
- Keep discovery output, implementation, generated schemas, host registration, allowlists, and documentation synchronized.
- Define idempotency, cancellation, progress, partial results, artifacts, and retry behavior where operations can be long-running or repeated.
- Do not expose one unrestricted tool when several bounded capabilities can express the intended operations safely.

## Trust And Authorization

- Treat model output, prompt text, resource content, remote messages, tool results, and user-provided paths or commands as untrusted input.
- Validate inputs against the declared Schema and enforce authorization, workspace/path boundaries, risk policy, and confirmation at the execution owner.
- Do not expose arbitrary shell commands, arbitrary script paths, unrestricted filesystem/network access, or hidden privilege escalation through flexible parameters.
- Keep credentials and host secrets outside tool arguments, model-visible output, logs, fixtures, protocol examples, and source control.

## Transport And Lifecycle

- Follow the selected transport's framing, concurrency, reconnect, shutdown, and error requirements. Do not assume stdio, local-only, or unauthenticated operation unless verified.
- Apply timeouts, cancellation, output-size limits, resource cleanup, and backpressure to tool calls and transport streams.
- Separate natural-language interpretation from deterministic validation and execution. The execution boundary must reject unsupported actions or malformed parameters.

## Verification Gates

- Verify discovery/listing and at least one valid and invalid call for each changed tool or resource.
- Test Schema rejection, authorization denial, timeout, cancellation, duplicate/retried calls, structured errors, cleanup, and compatibility where applicable.
- Confirm real artifacts or files exist, are non-empty and correctly typed, and remain inside authorized locations when tools produce them.
- Run host/client integration or protocol conformance checks when available; unit tests alone do not prove registration and transport behavior.
