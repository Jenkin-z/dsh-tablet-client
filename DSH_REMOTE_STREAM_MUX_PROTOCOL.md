# DSH Remote Stream Mux — Host Wire Protocol Specification

Evidence base: `D:\software\deepseek-harness` (read-only inspection).
Every claim below carries `file:line`. Claims marked **[VERIFIED]** are read directly from Host
implementation code or from literal test transcripts. **[INFERRED]** marks a conclusion drawn from
code that does not literally print the wire value. **[AMBIGUOUS]** marks genuine uncertainty.

---

## 0. Transport substrate

### 0.1 The one WebSocket route

`packages/api/gateway/src/stream-protocol.ts:6`

```ts
/** Exact WebSocket route carrying every Typert Remote stream. */
export const REMOTE_STREAM_MUX_PATH = '/api/remote.mux'
```

**[VERIFIED]** All logical streams (including `$events`, `session/follow`, `session/control`,
`workspace/follow`) share ONE physical WebSocket at `/api/remote.mux`. Upgraded on the same HTTP
server/port as `/api`. Upgrade route registration: `packages/api/gateway/src/index.ts:212-228`.

### 0.2 WebSocket authentication

The upgrade request is rejected before `ws` takes socket ownership if it fails the Host/Origin
fence or browser auth (`packages/api/gateway/src/index.ts:214-221`):

```ts
handler: (req, socket, head) => {
  const rejection = webCtx.connection.requestRejection(req)
  if (rejection !== undefined) {
    rejectRemoteStreamUpgrade(socket, rejection)
    return
  }
  mux.handleUpgrade(req, socket, head)
},
```

`requestRejection` (`packages/client/connection/src/rpc-host.ts:97-100`):

```ts
requestRejection(request: ConnectionTrustRequest): ConnectionRequestRejection {
  if (!isTrustedApiRequest(request, this.trustedHosts)) return 403
  return this.browserAuth.isAuthenticated(request) ? undefined : 401
}
```

Rejection is a plain HTTP response written onto the raw socket, NOT a WebSocket close
(`packages/api/gateway/src/stream-server.ts:213-224`):

```
HTTP/1.1 401 Unauthorized
Connection: close
Content-Type: text/plain; charset=utf-8
Content-Length: 12

unauthorized
```
(status 403 → `Forbidden` / `forbidden`)

**[VERIFIED]** The credential is a `Cookie` header with the `dsh-auth-<authority>` cookie
(`packages/client/connection/src/browser-auth.ts:16`, `:293`). Client usage in tests:

- `packages/api/gateway/tests/gateway-stream.host.spec.ts:1002-1004`
  ```ts
  const socket = new WebSocket(`${origin.replace('http:', 'ws:')}/api/remote.mux`, {
    headers: { cookie },
  })
  ```
- `apps/web/tests/smoke-real.e2e.ts:114-116`
  ```ts
  const socket = new WebSocket(`${authenticated.origin.replace(/^http/u, 'ws')}/api/remote.mux`, {
    headers: { cookie: authenticated.cookie },
  })
  ```

The cookie is obtained by opening the URL printed by `dsh web` (carries `?token=<process launch
token>`); the server exchanges it for a `Set-Cookie` (`packages/client/connection/src/browser-auth.ts:304-312`,
`packages/api/gateway/tests/gateway-stream.host.spec.ts:50-69`).

### 0.3 Physical socket control frames

**Ping/Pong** — the Host pings every `websocketHeartbeatIntervalMs` (default `2_000` ms,
`packages/api/gateway/src/index.ts:116`, `:172-173`). Default config assertion:
`packages/api/gateway/tests/gateway-stream.host.spec.ts:222`.

```ts
expect(TypertGatewayService.Config({})).toEqual({ websocketHeartbeatIntervalMs: 2_000 })
```

After `MAX_MISSED_HEARTBEATS = 2` unanswered pings the Host calls `socket.terminate()`
(`packages/api/gateway/src/stream-server.ts:22`, `:80-89`). **[VERIFIED]** A client MUST answer
WebSocket pings (or any conforming WS library does automatically).

**Binary messages are refused** (`packages/api/gateway/src/stream-server.ts:116-120`):

```ts
this.socket.on('message', (data, isBinary) => {
  if (isBinary) {
    this.socket.close(1003, 'text messages required')
    return
  }
  try {
    this.receive(rawText(data))
  } catch {
    this.socket.close(1008, 'invalid Remote stream request')
  }
})
```

**[VERIFIED]** Close codes: `1003` for any binary frame, `1008` for any text frame that fails
`parseRemoteStreamClientMessage`, `1011` when a terminal `error` frame cannot be encoded/written
(`packages/api/gateway/src/stream-server.ts:174`).

---

## 1. Logical-stream multiplexing envelope

### 1.1 Client → Host messages

`packages/api/gateway/src/stream-protocol.ts:242-250`

```ts
/** One logical stream request sent from the browser. */
export type RemoteStreamClientMessage =
  | {
    readonly type: 'open'
    readonly streamId: string
    readonly endpoint: string
    readonly payload: unknown
  }
  | { readonly type: 'cancel'; readonly streamId: string }
```

**[VERIFIED]** Exactly two client message types, and the parser enforces EXACT keys
(`packages/api/gateway/src/stream-protocol.ts:270-275`, `exactKeys` at `:276+`). No extra fields.

Literal `open` (test helper, used for every stream):
`packages/api/gateway/tests/gateway-stream.host.spec.ts:1070-1072`

```ts
function sendOpen(socket: WebSocket, streamId: string, endpoint: string, args: object): void {
  socket.send(JSON.stringify({ type: 'open', streamId, endpoint, payload: { args } }))
}
```

Literal `cancel` (`packages/api/gateway/tests/gateway-stream.host.spec.ts:332`):

```ts
socket.send(JSON.stringify({ type: 'cancel', streamId: 'a' }))
```

- `streamId` is client-minted and opaque. Reusing an id while that stream is live throws
  `api gateway: duplicate Remote stream id …` (`packages/api/gateway/src/stream-server.ts:140-142`),
  which propagates out of `receive()` and closes the socket with `1008`.
- `payload` MUST be an object with exactly one plain-object `args` field
  (`packages/api/gateway/src/index.ts:936-951`):

```ts
function remoteRequest(endpoint: string, payload: unknown, signal: AbortSignal): InvokeRemoteRequest {
  const segments = endpoint.split('/')
  if (segments.length !== 2 || segments[0] === '' || segments[1] === '') {
    throw new Error(`invalid Remote endpoint ${JSON.stringify(endpoint)}`)
  }
  const [namespace, method] = segments as [string, string]
  if (!isObject(payload)
    || !isPlainObject(payload)
    || Reflect.ownKeys(payload).length !== 1
    || !Object.hasOwn(payload, 'args')
    || !isObject(payload.args)
    || !isPlainObject(payload.args)) {
    throw new Error('Remote payload must contain exactly one plain-object args field')
  }
  return { namespace, method, args: payload.args, signal }
}
```

**[VERIFIED] IMPORTANT for the Flutter client:** the endpoint is ALWAYS exactly two `/`-separated
segments — `namespace/method`. `$events` and `session/follow` are the two-segment forms of the
internal stream names. `$events/result` (three segments) is NOT a stream; it is an HTTP RPC
path only. `args` is a **named-field object**, not an array.

Names that are single-word functions (e.g. `workspace/follow` takes only `signal`) still require
`payload: { args: {} }` — an empty args object.

### 1.2 Host → Client messages

`packages/api/gateway/src/stream-protocol.ts:252-263`

```ts
/** Carrier-safe failure delivered by the Host. */
export interface RemoteStreamFailure {
  readonly code: string
  readonly message: string
  readonly details: object
}

/** One logical stream frame sent from the Host. */
export type RemoteStreamServerMessage =
  | { readonly type: 'item'; readonly streamId: string; readonly value?: unknown }
  | { readonly type: 'error'; readonly streamId: string; readonly error: RemoteStreamFailure }
  | { readonly type: 'end'; readonly streamId: string }
```

**[VERIFIED]** Every Host frame carries `streamId`. `value` is optional on `item` — the emitter
omits the key when the yielded value is `undefined` (`packages/api/gateway/src/stream-server.ts:164`,
`this.send({ type: 'item', streamId, value })` — the key is always present in the object literal;
`JSON.stringify` drops it only for `undefined`).

Emission logic (`packages/api/gateway/src/stream-server.ts:155-178`):

```ts
private async pump(streamId, endpoint, payload, active): Promise<void> {
  try {
    const source = await this.open(endpoint, payload, active.abort.signal)
    for await (const value of source) {
      await this.send({ type: 'item', streamId, value })
    }
    if (!active.abort.signal.aborted) await this.send({ type: 'end', streamId })
  } catch (error) {
    if (!active.abort.signal.aborted && this.socket.readyState === WebSocket.OPEN) {
      try {
        await this.send({ type: 'error', streamId, error: this.failure(error) })
      } catch {
        this.socket.close(1011, 'Remote stream failure could not be delivered')
      }
    }
  }
}
```

**[VERIFIED]** After `cancel`, the Host does NOT send `end` or `error` for that stream — the
`abort.signal.aborted` guard suppresses both. The client learns of cancellation only from its own
local close. Literal transcript (`packages/api/gateway/tests/gateway-stream.host.spec.ts:342-346`):

```ts
expect(frames.filter(frame => frame.streamId === 'sync')).toEqual([
  { type: 'item', streamId: 'sync', value: 's:one' },
  { type: 'item', streamId: 'sync', value: 's:two' },
  { type: 'end', streamId: 'sync' },
])
```

Literal error frame (`packages/api/gateway/tests/gateway-stream.host.spec.ts:354-362`):

```ts
expect(frames.find(frame => frame.streamId === 'rejected')).toEqual({
  type: 'error',
  streamId: 'rejected',
  error: {
    code: 'fixture/rejected',
    message: 'fixture rejected the stream',
    details: { retryable: false },
  },
})
```

Error mapping (`packages/api/gateway/src/index.ts:993-1010`): a `RemoteError` keeps its
`code`/`message`/`details`; anything else becomes `code: 'gateway/internal'`, `details: {}`.

---

## 2. The `$events` logical stream

### 2.1 Opening message

```jsonc
{
  "type": "open",
  "streamId": "<any client-minted string>",
  "endpoint": "$events",
  "payload": { "args": {} }
}
```

Evidence:
- Endpoint constant `packages/api/gateway/src/stream-protocol.ts:9`
  ```ts
  export const REMOTE_EVENT_STREAM_ENDPOINT = '$events'
  ```
- Payload constant `packages/api/gateway/src/stream-protocol.ts:15`
  ```ts
  export const REMOTE_EVENT_STREAM_PAYLOAD = { args: {} } as const
  ```
- Literal send `packages/api/gateway/tests/gateway-stream.host.spec.ts:1008` → `sendOpen(socket, streamId, '$events', {})`
  which serializes to `payload: { args: {} }`.
- Also `:404` → `sendOpen(socket, 'events', '$events', {})`.

**[VERIFIED]** The `args` object MUST be empty. `packages/api/gateway/src/index.ts:394-403`:

```ts
if (Reflect.ownKeys(args).length !== 0) {
  throw new TypertGatewayError(
    'gateway/arguments-invalid',
    REMOTE_EVENT_STREAM_ENDPOINT,
    'forwarded Remote event stream requires an empty args object',
  )
}
```

An unavailable event source yields `gateway/service-unavailable` (`:404-411`).

### 2.2 Downlink frame shapes

Discriminated union, `packages/api/gateway/src/stream-protocol.ts:33-70`:

```ts
export interface RemoteEventReadyFrame {
  readonly type: 'ready'
  readonly clientId: RemoteEventClientId
  readonly host: RemoteEventHostInfo      // { home: string }
}

export interface RemoteEventEmitFrame {
  readonly type: 'emit'
  readonly event: string
  readonly args: readonly unknown[]
}

export interface RemoteEventInvocationFrame {
  readonly type: 'waterfall'
  readonly event: string
  readonly eventId: RemoteEventId
  readonly agentId: RemoteEventAgentId
  readonly request: Readonly<Record<string, unknown>>
}

export interface RemoteEventCancellationFrame {
  readonly type: 'cancel'
  readonly eventId: RemoteEventId
}

export type RemoteEventDownlinkFrame =
  | RemoteEventReadyFrame
  | RemoteEventEmitFrame
  | RemoteEventInvocationFrame
  | RemoteEventCancellationFrame
```

`RemoteEventHostInfo` (`packages/api/gateway/src/stream-protocol.ts:27-30`): `{ home: string }`,
set from `homedir()` (`packages/api/remotes/src/index.ts:42`).

**These four objects are the `value` of a `{type:'item'}` envelope.** They are NOT themselves
socket frames. Literal transcript showing the wrapping
(`packages/api/gateway/tests/gateway-stream.host.spec.ts:406-426`):

```ts
const eventFrames = frames.filter(frame => frame.streamId === 'events')
expect(eventFrames).toHaveLength(1)
expect(eventFrames[0]).toMatchObject({
  type: 'item', streamId: 'events', value: { type: 'ready', host: REMOTE_HOST },
})
expect(typeof Reflect.get(eventFrames[0]!.value as object, 'clientId')).toBe('string')
...
expect(eventFrames[1]).toEqual({
  type: 'item', streamId: 'events', value: {
    type: 'emit', event: 'fixture/changed', args: ['settings'],
  },
})
```

Where `REMOTE_HOST = { home: '/home/fixture' }` (`packages/api/gateway/tests/gateway-stream.host.spec.ts:46`).

#### literal `ready`

```json
{"type":"item","streamId":"events","value":{"type":"ready","clientId":"3f1c...-uuid","host":{"home":"/home/fixture"}}}
```

Host emission, `packages/api/gateway/src/index.ts:423`:

```ts
yield { ...REMOTE_EVENT_STREAM_READY, clientId, host: registration.host }
```
with `REMOTE_EVENT_STREAM_READY = { type: 'ready' }` (`stream-protocol.ts:18`) and
`clientId` a fresh `randomUUID()` (`index.ts:413-414`).

**[VERIFIED]** `ready` is always the FIRST item on `$events`, once per generation. `clientId` is
required for `$events/result` correlation. `host.home` is the Host account home.

#### literal `emit`

```json
{"type":"item","streamId":"events","value":{"type":"emit","event":"api-session/status","args":["session-1",true]}}
```

Host emission, `packages/api/gateway/src/index.ts:447-455`:

```ts
private broadcastRemoteEvent(frame: TypertRemoteEventFrame): void {
  assertRemoteEventFrame(frame)
  const wire: RemoteEventEmitFrame = { type: 'emit', event: frame.event, args: frame.args }
  for (const client of this.remoteEventClients.values()) client.queue.push(wire)
}
```

`args` is a JSON array of the Cordis listener's positional arguments, in order. Real client-side
consumption examples (`packages/api/session-controller/tests/client-apply.client.spec.ts:54-68`):

```ts
await emit(mock, 'api-session/added', { sessionId: sid('session-1'), updatedAt: 1, running: false, blank: true })
await emit(mock, 'api-session/status', sid('session-1'), true)
await emit(mock, 'api-session/activity', sid('session-1'), 9)
await emit(mock, 'api-session/error', sid('session-1'), 'agent failed')
await emit(mock, 'api-session/removed', sid('session-1'))
```
where `emit` is (`:37-40`):
```ts
async function emit(mock: RemoteMock, event: string, ...args: unknown[]): Promise<void> {
  mock.streams.push(EVENTS, { type: 'emit', event, args })
  await mock.streams.drained(EVENTS)
}
```

**[VERIFIED]** Non-JSON arguments throw at the source
(`packages/api/remotes/src/index.ts:160-167`): `forwarded host event "<event>" argument <n> is not
lossless JSON data`.

#### literal `waterfall`

```json
{"type":"item","streamId":"events","value":{
  "type":"waterfall",
  "event":"approval/request",
  "eventId":"9a0f...-uuid",
  "agentId":"<session-or-agent-id>",
  "request":{"toolName":"pwsh","callId":"call-1","reason":"..."}
}}
```

Host construction, `packages/api/gateway/src/index.ts:491-506`:

```ts
const pending: PendingRemoteEvent = {
  id,
  source,
  frame: {
    type: 'waterfall',
    event: source.event,
    eventId: id,
    agentId: source.context.agentId,
    request: projected.request,
  },
  deliveries: new Set(),
  releaseContext,
  releaseSignal: () => { for (const signal of signals) signal.removeEventListener('abort', abort) },
}
```

**Answer to the `agentId` question.** **[VERIFIED]** Identity is carried in BOTH places, and they
are the same value:

1. `frame.agentId` — from `source.context.agentId` (`index.ts:498`), and it is REQUIRED non-empty
   (`index.ts:460-464`):
   ```ts
   if (!isRemoteEventAgentId(source.context.agentId)) {
     throw new TypeError('typert gateway: scoped Remote events require a non-empty Agent identity')
   }
   ```
2. The `agent` field that used to sit inside `request` is **STRIPPED** for transport
   (`packages/api/gateway/src/stream-protocol.ts:139-172`):
   ```ts
   export function projectRemoteEventRequest(value, subject): ProjectedRemoteEventRequest {
     if (!isPlainRecord(value) || !Object.hasOwn(value, 'agent') || value.agent !== subject) {
       throw new TypeError('api gateway: Remote event request must carry its scoped Agent directly')
     }
     const signal = value.signal
     ...
     const request: Record<string, unknown> = Object.create(null) as Record<string, unknown>
     for (const key of Reflect.ownKeys(value)) {
       if (key === 'agent' || key === 'signal') continue
       ...
       request[key] = Reflect.get(value, key)
     }
     ...
   }
   ```
   So `request` on the wire contains NEITHER `agent` NOR `signal`. The client re-attaches its own
   `agent` when dispatching locally (`packages/api/gateway/src/client/remote-events.ts:228-232`):
   ```ts
   const request = {
     ...frame.request,
     agent: target,
     signal,
   }
   ```

The client-side validator confirms both facts (`packages/api/gateway/src/client/remote-events.ts:291-307`):

```ts
if (value.type === 'waterfall'
  && hasExactRemoteEventKeys(value, ['type', 'event', 'eventId', 'agentId', 'request'])
  && validRemoteEventName(value.event)
  && isRemoteEventId(value.eventId)
  && isRemoteEventAgentId(value.agentId)
  && isRemoteEventRecord(value.request)
  && !Object.hasOwn(value.request, 'agent')
  && !Object.hasOwn(value.request, 'signal')
  && isRemoteJsonValue(value.request)) {
```

**[VERIFIED]** Exact key set on a `waterfall` frame: `type`, `event`, `eventId`, `agentId`,
`request`. No other keys are tolerated.

##### `request` contents for the two waterfall events

The allowlist (`packages/api/remotes/src/remote-events.ts:17-38`) declares exactly TWO waterfall
events — everything else is `emit`:

```ts
export const API_REMOTE_FORWARDED_EVENTS = [
  { event: 'agent-preset/selected', mode: 'emit' },
  { event: 'approval/request', mode: 'waterfall' },
  { event: 'api-session/activity', mode: 'emit' },
  { event: 'api-session/added', mode: 'emit' },
  { event: 'api-session/error', mode: 'emit' },
  { event: 'api-session/removed', mode: 'emit' },
  { event: 'api-session/status', mode: 'emit' },
  { event: 'commands/change', mode: 'emit' },
  { event: 'credentials/reference-updated', mode: 'emit' },
  { event: 'goal/activation-changed', mode: 'emit' },
  { event: 'cordis/request-run', mode: 'emit' },
  { event: 'cordis/request-run-resolved', mode: 'emit' },
  { event: 'cordis/dynamic-package', mode: 'emit' },
  { event: 'cordis/dynamic-retract', mode: 'emit' },
  { event: 'cordis/inspect-query', mode: 'emit' },
  { event: 'cordis/inspect-query-resolved', mode: 'emit' },
  { event: 'llm/adapters-updated', mode: 'emit' },
  { event: 'permission-presets/catalog-changed', mode: 'emit' },
  { event: 'settings/document-updated', mode: 'emit' },
  { event: 'user-questions/request', mode: 'waterfall' },
] as const satisfies readonly TypertForwardableEventEntry[]
```

**`approval/request`** — `event` string is exactly `"approval/request"`.
Source type `ApprovalRequestEvent` (`packages/interaction/user-approval/src/types.ts:62-74`):

```ts
export interface ApprovalRequestEvent {
  readonly agent: Agent
  readonly toolName: string
  readonly callId?: ToolCallId
  readonly reason?: string
  readonly signal?: AbortSignal
}
```

Minus `agent` and `signal` (stripped), and minus `undefined` keys (never JSON-serialized):

```json
"request": { "toolName": "pwsh" }
```
```json
"request": { "toolName": "pwsh", "callId": "call_abc", "reason": "hook asked for a decision" }
```

**[VERIFIED]** from the type and the strip loop. `callId` and `reason` are optional and only appear
when the asker supplied them.

The dispatch path (`packages/interaction/user-approval/src/index.ts:273-277`) confirms `req` is the
object handed to the waterfall:
```ts
const answer: Promise<ApprovalOutcome> = Promise.resolve().then(
  () => this.ctx.waterfall(
    scopeTarget(req.agent, req.agent), 'approval/request', req,
    () => Promise.resolve<ApprovalOutcome>('unavailable'),
  ),
)
```

Reply value type (`packages/interaction/user-approval/src/types.ts:32`):

```ts
export type ApprovalOutcome = 'allowed-once' | 'rejected' | 'cancelled' | 'unavailable'
```

The client UI reads exactly `toolName`, `callId`, `reason`, `signal`
(`packages/client/ui-approval/src/client/index.ts:44-51`) — confirming no other host fields exist.

**`user-questions/request`** — `event` string is exactly `"user-questions/request"`.
Source type `AskUserQuestionRequestEvent` (`packages/interaction/user-questions/src/types.ts:66-74`):

```ts
export interface AskUserQuestionRequestEvent {
  questions: AskUserQuestionItem[]
  agent?: Agent
  signal?: AbortSignal
}
```

Minus `agent` (always present here — see below) and `signal`:

```json
"request": {
  "questions": [
    {
      "id": "q1",
      "question": "Which environment?",
      "detail": "optional supporting text",
      "header": "optional short heading",
      "options": [
        { "label": "staging", "description": "optional extra context" },
        { "label": "production" }
      ],
      "multiSelect": false,
      "intent": { "kind": "plan-review", "approve": "staging" }
    }
  ]
}
```

Item/option/answer types: `packages/interaction/user-questions/src/types.ts:7-64`.

**[VERIFIED]** `agent` is present and identical to `frame.agentId` for this event. In the ask
path (`packages/interaction/user-questions/src/index.ts:134-142`) the agent-carrying branch is the
one that reaches the forwarded waterfall with `agent` inside the request:

```ts
return await (agent === undefined
  ? this.ctx.waterfall('user-questions/request', request, noAnswerer)
  : this.ctx.waterfall(
    scopeTarget(agent, agent),
    'user-questions/request',
    { ...request, agent },
    noAnswerer,
  ))
```

And the forwarding listener enforces it (`packages/api/remotes/src/index.ts:57-75`):

```ts
return ctx.on(event as never, (function (this: unknown, request: object, next: () => unknown) {
  const carrierAgent = carrierKeyOf(this)
  if (carrierAgent === undefined) return next()
  const agent = (request as { readonly agent?: Agent }).agent
  if (agent === undefined || agent !== carrierAgent) {
    throw new TypeError(`forwarded scoped event ${JSON.stringify(event)} must carry its Agent directly`)
  }
  return forwardWaterfall(
    queue, event, request,
    { value: agent.ctx, subject: agent, agentId: agent.id },
    next,
  )
}) as never)
```

**[VERIFIED — important]** The `agent === undefined` branch of `user-questions.ask()` dispatches a
NON-agent-scoped waterfall, which the forwarder's `carrierKeyOf(this) === undefined` guard passes
straight to `next()`. Such a request is therefore **never forwarded** to a client. Every
`user-questions/request` frame a Flutter client sees carries an `agent` in the source request, so
`frame.agentId` is always meaningful for this event.

Test evidence for the wire shape (`packages/api/remotes/tests/remote-events.host.spec.ts:243-249`):

```ts
const pending = waterfallRaw(
  ctx,
  scopeTarget(ctx, agent),
  'user-questions/request',
  [{ questions: [], agent }],
  () => Promise.resolve('host fallback'),
)
```
and `:183-221` (the same shape for the `'user-questions/request'` event name).

`AskUserQuestionAnswer` reply type (`packages/interaction/user-questions/src/types.ts:60-64`):

```ts
export interface AskUserQuestionAnswer {
  answers: AskUserQuestionAnswerItem[]   // { id, selected: string[], custom?: string }
}
```

#### literal `cancel`

```json
{"type":"item","streamId":"events","value":{"type":"cancel","eventId":"9a0f...-uuid"}}
```

Client handling (`packages/api/gateway/src/client/remote-events.ts:147-150`):

```ts
if (frame.type === 'cancel') {
  active.get(frame.eventId)?.abort(new Error('client api: Remote event was cancelled by the Host'))
  continue
}
```

Real fixture (`apps/web/tests/assembled-remote.ts:201-205`):

```ts
mock.unary('$events/result', (result: unknown) => {
  const eventId = recordString(result, 'eventId')
  mock.streams.push('$events', { type: 'cancel', eventId })
  return ok(undefined)
})
```

**[VERIFIED]** `cancel` is emitted by the Host when a pending waterfall's lifetime ends without an
answer (`packages/api/gateway/src/index.ts:485-490`, `cancelRemoteEvent`). It carries ONLY
`eventId` — never `streamId` in the inner object (the outer `item` carries that).

### 2.3 The client's reply: `$events/result`

Client call site (`packages/api/gateway/src/client/remote-events.ts:207-220`):

```ts
const result: RemoteEventResult = {
  clientId,
  eventId: frame.eventId,
  outcome: outcome.kind === 'result' && outcome.value === undefined
    ? { kind: 'result' }
    : outcome,
}
const response = await this.connection.rpc.call(
  '/api',
  REMOTE_EVENT_RESULT_ENDPOINT,
  { args: result },
  signal,
)
if (!response.ok) throw new Error(response.error.message)
```

See §3 for the full HTTP envelope. `REMOTE_EVENT_RESULT_ENDPOINT = '$events/result'`
(`packages/api/gateway/src/stream-protocol.ts:12`).

Result union (`packages/api/gateway/src/stream-protocol.ts:78-94`):

```ts
export interface RemoteEventRejection {
  readonly name: string
  readonly message: string
  readonly code?: string
  readonly details?: unknown
}

export interface RemoteEventResult {
  readonly clientId: RemoteEventClientId
  readonly eventId: RemoteEventId
  readonly outcome:
    | { readonly kind: 'next' }
    | { readonly kind: 'result'; readonly value?: unknown }
    | { readonly kind: 'rejected'; readonly error: RemoteEventRejection }
}
```

Parser constraints (`packages/api/gateway/src/stream-protocol.ts:101-137`) — **[VERIFIED]**:

- Outer object keys are EXACTLY `clientId`, `eventId`, `outcome`.
- `outcome.kind: 'next'` → keys exactly `['kind']`.
- `outcome.kind: 'result'` → keys exactly `['kind']` OR exactly `['kind','value']`; when `value` is
  present it must be lossless JSON.
- `outcome.kind: 'rejected'` → keys exactly `['kind','error']`.
- Anything else throws `api gateway: invalid Remote event result`.

---

## 3. The `$events/result` HTTP RPC

### 3.1 Method, path, headers

**[VERIFIED]** — from the test's real `fetch` call
(`packages/api/gateway/tests/gateway-stream.host.spec.ts:1051-1062`):

```ts
const response = await fetch(`${client.origin}/api/$events/result`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', cookie: client.cookie },
  body: JSON.stringify({
    type: 'client-request',
    rpcId,
    method: '$events/result',
    payload: {
      args: { clientId: client.clientId, eventId: frame.eventId, outcome },
    },
  }),
})
expect(response.status).toBe(200)
```

- **Method:** `POST` (any other method → `404`, `packages/client/connection/src/rpc-host.ts:217-219`)
- **Path:** `/api/$events/result` (exact, case-sensitive)
- **`content-type: application/json`** is mandatory — the leading media type must be exactly
  `application/json`, else `415 content type must be application/json`
  (`packages/client/connection/src/rpc-host.ts:221-224`)
- **`cookie: dsh-auth-<authority>=…`** mandatory, else `401 unauthorized`
- Body limit: `DEFAULT_MAX_REQUEST_BODY_BYTES = 300 * 1024 * 1024`, exceeding → `413`
  (`packages/client/connection/src/http-bridge.ts:14`, `:47-54`)

### 3.2 Request body envelope

```jsonc
{
  "type": "client-request",
  "rpcId": "remote-event-result-events",
  "method": "$events/result",
  "payload": {
    "args": {
      "clientId": "<clientId from the ready frame>",
      "eventId": "<eventId from the waterfall frame>",
      "outcome": { "kind": "result", "value": "allowed-once" }
    }
  }
}
```

Schema (`packages/client/connection/src/rpc-schema.ts:35-40`):

```ts
export const clientRequestSchema = z.object({
  type: z.literal('client-request'),
  rpcId: rpcIdSchema,                       // z.string()
  method: z.string(),
  payload: z.unknown(),
}) as z.ZodType<ClientRequest>
```

**`method` MUST equal the path's endpoint** (`packages/client/connection/src/rpc-host.ts:238-244`):

```ts
if (message.method !== endpoint) {
  return errorResponse(message.rpcId, {
    code: 'gateway/bad-request',
    message: `method ${JSON.stringify(message.method)} does not match endpoint ${JSON.stringify(endpoint)}`,
    details: { issues: [] },
  })
}
```

The Host then requires `payload` to be EXACTLY `{ args }` with `args` a plain object
(`packages/api/gateway/src/index.ts:926-934`):

```ts
function parseRemoteEventResultPayload(payload: unknown): ReturnType<typeof parseRemoteEventResult> {
  if (!isObject(payload)
    || !isPlainObject(payload)
    || Reflect.ownKeys(payload).length !== 1
    || !Object.hasOwn(payload, 'args')) {
    throw new Error('typert gateway: Remote event result requires exactly one plain-object args field')
  }
  return parseRemoteEventResult(payload.args)
}
```

### 3.3 Success response body envelope

Handler (`packages/api/gateway/src/index.ts:352-371`):

```ts
private async dispatchRpc(
  endpoint: string,
  payload: unknown,
  signal: AbortSignal,
): Promise<ConnectionRpcResult> {
  if (endpoint === REMOTE_EVENT_RESULT_ENDPOINT) {
    try {
      const result = parseRemoteEventResultPayload(payload)
      const client = this.remoteEventClients.get(result.clientId)
      if (client === undefined) {
        throw new Error('typert gateway: Remote event result identifies no active event stream')
      }
      this.receiveRemoteEventResult(client, result)
      return { ok: true, value: undefined }
    } catch (error) {
      return rpcFailure(error)
    }
  }
  return this.invokeRpc(endpoint, payload, signal)
}
```

Envelope construction (`packages/client/connection/src/rpc-host.ts:281-284`):

```ts
function fullResponse(rpcId: RpcIdType, result: ConnectionRpcResult<unknown>): Response {
  const body: ConnectionServerResponse = { type: 'server-response', rpcId, result }
  return Response.json(body)
}
```

**[VERIFIED] Answer to "is it `{result:{ok:true}}` or something else":**

It is `{ type, rpcId, result }` — and success is discriminated by **`result.ok === true`**, NOT by
a nested `{ok:true}` payload:

```json
{"type":"server-response","rpcId":"remote-event-result-events","result":{"ok":true}}
```

**[VERIFIED]** Note there is **no `value` key at all** on success — the Host returns
`{ ok: true, value: undefined }` and `JSON.stringify` drops `value: undefined`. The test's own
assertion reads the shape directly (`packages/api/gateway/tests/gateway-stream.host.spec.ts:1064-1067`):

```ts
const body = await response.json() as { readonly result?: { readonly ok?: boolean; readonly error?: { message?: string } } }
if (body.result?.ok !== true) {
  throw new Error(body.result?.error?.message ?? 'Remote event result failed')
}
```

**HTTP status is `200` even on logical failure.** A rejected result body is
(`packages/client/connection/src/rpc-host.ts:277-279`):

```json
{"type":"server-response","rpcId":"…","result":{"ok":false,"error":{"code":"gateway/internal","message":"typert gateway: Remote event result identifies no active event stream","details":{}}}}
```

**[VERIFIED]** — `errorResponse` calls `fullResponse(...)` which uses `Response.json(body)` with no
status argument, i.e. `200`. Error codes from `rpcFailure` (`packages/api/gateway/src/index.ts:993-1006`):
a `RemoteError` keeps its own code; any other throw becomes `gateway/internal` with
`details: {}`.

Non-200 statuses on this route are purely transport-level:

| Status | Body | Cause |
|---|---|---|
| `401` | `unauthorized` | missing/invalid cookie (`rpc-host.ts:171-172`) |
| `403` | `forbidden` | Host/Origin fence (`rpc-host.ts:171-172`) |
| `404` | `not found` | wrong method, unclaimed endpoint, malformed path (`rpc-host.ts:132`, `:217-219`) |
| `413` | *(empty)* | body over the cap (`http-bridge.ts:49-53`, `:60-64`) |
| `415` | `content type must be application/json` | bad/missing content-type (`rpc-host.ts:221-224`) |
| `400` | `body is not JSON` | unparsable JSON (`rpc-host.ts:227-231`) |
| `500` | `handler failure: <string>` | the handler itself threw (`rpc-host.ts:249-251`) |

Invalid `client-request` envelope (any field wrong type or missing) still returns HTTP 200 with
(`packages/client/connection/src/rpc-host.ts:256-264`):

```json
{"type":"server-response","rpcId":"invalid-request","result":{"ok":false,"error":{"code":"gateway/bad-request","message":"invalid client-request message","details":{"issues":[…]}}}}
```

**[VERIFIED]** — `rpcId` is echoed from the (possibly invalid) request body if it is a string,
otherwise the literal `"invalid-request"` (`rpc-host.ts:31`, `:257-258`).

---

## 4. The `session/follow` logical stream

### 4.1 Existence and opening message

**[VERIFIED]** — `'session/follow'` is a real endpoint
(`packages/api/session-controller/tests/remote/session.client.ts:25`):

```ts
export const FOLLOW = 'session/follow'
```

Registered host-side (`packages/api/session-controller/src/index.ts:400-403`):

```ts
@Remote({ mode: 'stream' })
follow(request: SessionFollowRequest, signal: AbortSignal): AsyncIterable<SessionFollowFrame> {
  return this.history.follow(request, signal)
}
```

Opening message (literal, from the real end-to-end smoke test,
`apps/web/tests/smoke-real.e2e.ts:184-189`):

```jsonc
{
  "type": "open",
  "streamId": "smoke-history-<uuid>",
  "endpoint": "session/follow",
  "payload": {
    "args": {
      "request": {
        "address": { "kind": "session", "sessionId": "<session-id>" }
      }
    }
  }
}
```

**Critical envelope detail.** The Remote signature is `follow(request, signal)`. The `request`
parameter is the FIRST positional parameter, so its wire field is **`request`**. `signal` is
transport-injected and never enters `args` (`packages/api/gateway/src/index.ts:673-685`, which
detects a trailing `signal` parameter and declares `cancellation: { parameter: 'signal' }`).

Same shape in the client transport (`packages/api/session-controller/src/client/transport.ts:179-183`):

```ts
for await (const frame of this.remote.session.follow({
  address: this.address,
  assistantStream: true,
  ...(request.maxMessages === undefined ? {} : { maxMessages: request.maxMessages }),
}, signal)) {
```

**[VERIFIED]** Request shape (`packages/api/session-controller/src/types.ts:439-454`):

```ts
export interface SessionPageRequest {
  readonly address: SessionAddress
  readonly throughSeq: number
  readonly beforeSeq?: number
  readonly maxMessages?: number
}

export interface SessionFollowRequest {
  readonly address: SessionAddress
  readonly maxMessages?: number
  /** Include process-local assistant presentation frames for the Web client. */
  readonly assistantStream?: true
}
```

```ts
export type SessionAddress =
  | { readonly kind: 'session'; readonly sessionId: SessionId }
  | {
    readonly kind: 'subagent'
    readonly parentSessionId: SessionId
    readonly childSessionId: SessionId
    readonly mode: 'one-shot' | 'continuable'
  }
```
(`packages/api/session-controller/src/types.ts:384-392`)

**[VERIFIED]** `assistantStream` is the literal boolean `true` (not a general boolean) when you
want `assistant-stream` frames. Omit it entirely (do not send `false`) to receive only durable
events. This is enforced client-side at `packages/api/session-controller/src/client/transport.ts:186-192`:
an omitted baseline for an opted-in request is a protocol error.

### 4.2 Downlink frame union

`packages/api/session-controller/src/types.ts:514-526`:

```ts
export type SessionFollowFrame =
  | {
    readonly type: 'snapshot'
    readonly header: SessionWireHeader
    readonly cursor: number
    readonly records: readonly SessionHistoryRecord[]
    readonly hasMore: boolean
    readonly projections: SessionProjectionBaseline
    readonly assistantStream?: SessionAssistantStreamBaseline
  }
  | SessionEventEntry
  | { readonly type: 'assistant-stream'; readonly frame: SessionAssistantStreamFrame }
```

**[VERIFIED] Important naming correction.** There is **no** frame `type` called
`snapshot`/`event`/`emit` in the sense the question implies:

- The opening frame is `"snapshot"`.
- A durable journal event frame is `SessionEventEntry` = `{ type: 'event', event: {...} }`
  (`packages/api/session-controller/src/types.ts:394-398`):
  ```ts
  export interface SessionEventEntry {
    readonly type: 'event'
    readonly event: SessionWireEvent
  }
  ```
- Transient live assistant chunks are `{ "type": "assistant-stream", "frame": {...} }`.
- **There is no `emit` frame on `session/follow`.** `emit` belongs to `$events` only (§2.2).
  If the current Flutter client expects `emit` here, that is a bug.

Each of these is again the `value` of a `{type:'item'}` envelope, e.g.:

```json
{"type":"item","streamId":"s1","value":{"type":"event","event":{"type":"user/message","seq":4,"time":1737000000000,"data":{…},"surfaceOp":"append"}}}
```

#### 4.2.1 `snapshot` — the opening frame

Field origins (`packages/api/session-controller/src/history.ts:190-211`):

```ts
yield {
  type: 'snapshot',
  header: wireHeader(source.header),
  cursor,
  records: pageRecords(events),
  hasMore,
  projections: address.kind === 'subagent' || source.projections === undefined
    ? { asOfSeq: cursor, values: {} }
    : projectionBlock(source.projections),
  ...assistantStream === undefined ? {} : { assistantStream },
}
```

`wireHeader` is a spread of the logical header (`:412-415`):

```ts
function wireHeader(header: SessionHeader): SessionWireHeader {
  return { ...header }
}
```

`SessionWireHeader` (`packages/api/session-controller/src/types.ts:400-412`):

```ts
export interface SessionWireHeader {
  readonly version: number
  readonly id: SessionId
  readonly createdAt: number
  readonly cwd?: string
  readonly parentSession?: SessionId
  readonly isSeeded: boolean
  readonly origin?: 'subagent'
  readonly delegationDepth?: number
  readonly agentPreset?: string
}
```

`records` — each record is a `SessionEventEntry`, i.e. `{ type:'event', event:{…} }`. Built by
`pageRecords` → `entryFor` (`history.ts:417-427`):

```ts
function entryFor(event: SessionEvent): SessionEventEntry {
  return {
    type: 'event',
    // Session.append validates and freezes event data as JSON before publication.
    event: event as unknown as SessionWireEvent,
  }
}

function pageRecords(events: readonly SessionEvent[]): SessionHistoryRecord[] {
  return events.map(entryFor)
}
```

`cursor`: last committed `seq` in the snapshot window, or `-1` for an empty log
(`packages/api/session-controller/tests/remote/history.client.ts:29`,
`apps/web/tests/assembled-remote.ts:193`).

`projections` — `SessionProjectionBaseline` (`packages/api/session-controller/src/types.ts:59-64`):

```ts
export interface SessionProjectionBaseline {
  readonly asOfSeq: number
  readonly values: SessionProjectionValues
}
```
`projectionBlock` (`history.ts:294-302`) maps `{ asOfSeq, values }` straight through.

`assistantStream` — `SessionAssistantStreamBaseline`
(`packages/api/session-controller/src/types.ts:469-473`):

```ts
export interface SessionAssistantStreamBaseline {
  readonly revision: number
  readonly activeAttempt?: SessionAssistantStreamAttempt
}
```

Literal `snapshot` (real wire-shaped JSON, from `apps/web/tests/assembled-remote.ts:184-198` plus the
snapshot builder `packages/api/session-controller/tests/remote/history.client.ts:33-47`):

```json
{
  "type": "snapshot",
  "header": {
    "version": 3,
    "id": "fx-alpha",
    "createdAt": 1737000000000,
    "cwd": "D:\\work\\alpha",
    "isSeeded": false
  },
  "cursor": 12,
  "records": [
    {
      "type": "event",
      "event": {
        "type": "user/message",
        "seq": 4,
        "time": 1737000000000,
        "data": {
          "id": "message-1",
          "role": "user",
          "content": [{ "type": "text", "text": "hello" }],
          "source": { "kind": "user" }
        },
        "surfaceOp": "append"
      }
    }
  ],
  "hasMore": false,
  "projections": { "asOfSeq": 12, "values": {} },
  "assistantStream": { "revision": 0 }
}
```

A subagent-addressed snapshot (`history.client.ts:35-42`):
```jsonc
"header": { "version": 3, "id": "<childSessionId>", "createdAt": 0, "isSeeded": false,
            "origin": "subagent", "parentSession": "<parentSessionId>" }
```

#### 4.2.2 `event` — durable journal frames

**[VERIFIED]** `SessionWireEvent` (`packages/api/session-controller/src/types.ts:427-437`):

```ts
export interface SessionWireEvent {
  readonly type: string
  readonly seq: number
  readonly time: number
  readonly data: JsonValue
  readonly ignorable?: true
  /** Earlier sources on current surface events; opaque JSON on unknown ignorable events. */
  readonly sourceEventSeqs?: JsonValue
  /** Canonical placement on current surface events; opaque JSON on unknown ignorable events. */
  readonly surfaceOp?: JsonValue
}
```

**Where does the diff `view` live?** **[VERIFIED] Inside `event.data.meta` on a
`tool/result` event — NOT on the event object, and NOT in a `view` field.** There is no event type
or field named `view` anywhere in the codebase (`grep "tool/view"` across `packages/` returns no
matches). See §4.2.5 below.

Durable events are streamed gap-free and seq-contiguous, with a hard protocol check
(`packages/api/session-controller/src/history.ts:225-231`):

```ts
const expectedSeq = SessionSeq(nextOffset)
if (item.event.seq < expectedSeq) continue
if (item.event.seq !== expectedSeq) {
  throw new RemoteError('gateway/internal', `session event stream skipped seq ${String(expectedSeq)}`, {})
}
nextOffset = SessionLogOffset(nextOffset + 1)
yield entryFor(item.event)
```

##### Exact journal event `type` strings and their `data`

Source of truth: `packages/core/session/src/types.ts:269-406` (`SessionEventMap`).

| `type` | `data` shape | Source |
|---|---|---|
| `turn/start` | `{ turn: number }` | `types.ts:276` |
| `turn/end` | `{ turn: number; reason: TurnEndReason }` | `types.ts:285` |
| `step/start` | `{ turn: number; step: number }` | `types.ts:287` |
| `step/end` | `{ turn: number; step: number }` | `types.ts:289` |
| `user/message` | `UserMessage` = `{ id, role:'user', content: ContentBlock[], source: MessageSource }` | `types.ts:297`, `packages/llm/llm/src/message.ts:131-145` |
| `system/message` | `{ turn, step, message: SystemMessage }` | `types.ts:310` |
| `assistant/message` | `{ turn, step, message: AssistantMessage, stream: AssistantStreamRecord[], usage?: TokenUsage, interrupted?: true }` | `types.ts:321-329` |
| `assistant/attempt` | `{ turn, step, stream: AssistantStreamRecord[] }` | `types.ts:335` |
| `tool/call` | `{ turn, step, callId: ToolCallId, name: string, arguments: string }` | `types.ts:341` |
| `tool/result` | `{ turn, step, message: ToolResultMessage, error?: {name,code,reason?}, meta?: JsonValue }` | `types.ts:355-365` |
| `request/header` | `{ header: EpochHeader, reason: RequestHeaderReason, startsSeries?: true }` | `types.ts:370-375` |
| `request/context` | `RequestContext` | `types.ts:382` |
| `session/end-seed` | `{ inherited?: true }` | `types.ts:405` |
| `approval/asked` | `{ id: ApprovalRequestId, toolName: string, callId?: ToolCallId, reason?: string }` | `packages/interaction/user-approval/src/types.ts:44-49` |
| `approval/decided` | `{ id: ApprovalRequestId, outcome: ApprovalOutcome }` | `packages/interaction/user-approval/src/types.ts:55-58` |
| `approval/policy` | `{ policy }` (read at `user-approval/src/index.ts:249`) | — |

**[VERIFIED]** `assistant/chunk` is **NOT** a current durable journal event type. It appears only
in legacy/migration fixtures (e.g. `packages/session/session-format-v1-to-v2/tests/migration.spec.ts:160`)
and in the format-v2→v3 migration that *removes* it
(`packages/session/session-format-v2-to-v3/tests/migration.spec.ts:196`:
`expect(output.events.filter(e => e.type === 'assistant/chunk')).toHaveLength(0)`).
Live chunking arrives instead as the transient `assistant-stream` frames (§4.2.3), and durably as
`assistant/message.data.stream` / `assistant/attempt.data.stream`.

Full literal `user/message` event (wire-shaped, from
`packages/api/session-controller/tests/sessions-service.client.spec.ts` fixtures and
`apps/web/tests/assembled-remote.ts:340-350`):

```json
{
  "type": "user/message",
  "seq": 4,
  "time": 1737000000000,
  "data": {
    "id": "message-1",
    "role": "user",
    "content": [{ "type": "text", "text": "hello" }],
    "source": { "kind": "user" }
  },
  "surfaceOp": "append"
}
```

Full literal `assistant/message` event — this is a REAL test fixture, verbatim from
`packages/api/session-controller/tests/sessions-service.client.spec.ts:162-178`:

```json
{
  "type": "event",
  "event": {
    "type": "assistant/message",
    "seq": 0,
    "time": 2,
    "data": {
      "turn": 1,
      "step": 1,
      "message": {
        "role": "assistant",
        "content": [{ "type": "text", "text": "live" }],
        "source": { "kind": "model", "provider": "p", "model": "m" },
        "id": "message-1"
      },
      "stream": [
        { "type": "text-chunks", "time0": 1, "index": 0, "dt": [], "texts": ["live"] }
      ]
    },
    "surfaceOp": "append"
  }
}
```

Full literal `tool/call`:
```json
{
  "type": "tool/call",
  "seq": 7,
  "time": 1737000001500,
  "data": {
    "turn": 1,
    "step": 1,
    "callId": "call_abc",
    "name": "read",
    "arguments": "{\"file_path\":\"D:\\\\work\\\\a.txt\"}"
  }
}
```
**[VERIFIED]** `arguments` is the raw, UNPARSED JSON string exactly as the model produced it
(`packages/core/session/src/types.ts:337-341`). The Flutter client must `jsonDecode` it itself.

Full literal `tool/result` **with the diff card** — the exact place the `view`/diff lives:
```json
{
  "type": "tool/result",
  "seq": 8,
  "time": 1737000001600,
  "data": {
    "turn": 1,
    "step": 1,
    "message": {
      "id": "message-2",
      "role": "user",
      "content": [{ "type": "tool-result", "callId": "call_abc", "content": [], "isError": false }],
      "source": { "kind": "tool", "callId": "call_abc", "name": "edit" }
    },
    "meta": {
      "diffs": [
        { "path": "D:\\work\\a.txt", "oldText": "before\n", "newText": "after\n" }
      ]
    }
  }
}
```

Evidence chain for `meta.diffs`:
- `packages/core/session/src/types.ts:342-365` documents `meta?: JsonValue` on `tool/result` as
  "opaque to the core … (e.g. `tool-fs` carries its result-time contextual diff here)".
- The producer: `packages/fs/tool-fs/src/diff.ts:20`
  ```ts
  export type FsDiffMeta = { diffs: FileDiff[] }
  ```
  and `packages/fs/tool-fs/src/edit.ts:108-111`:
  ```ts
  presentationMeta: (args, value) => ({
    diffs: computeHunkDiffs(args.file_path, value.before, value.after)
      .map(({ path, oldText, newText }) => ({ path, oldText, newText })),
  }),
  ```
- The consumer: `packages/fs/tool-fs/src/edit.ts:161-166` (`presentResult`) and
  `packages/fs/tool-fs/src/diff.ts:74-78` (`diffsFromMeta`) reading `meta.diffs`.
- `FileDiff` shape enforced by `isFileDiff` (`packages/fs/tool-fs/src/diff.ts:60-66`):
  `{ path: string, oldText: string|null, newText: string }`.
- `write` produces the same `meta.diffs` shape (`packages/fs/tool-fs/src/write.ts:99`, `:147-149`).

**[VERIFIED — the call-time counterpart.]** There is ALSO a call-time diff presentation
(`presentCall`, `packages/fs/tool-fs/src/edit.ts:151-158`) returning
`{ card: 'diff', title, diffs, locations }`. That is a *client-plugin rendering* return value, NOT
a durable journal field. **It does not appear on `session/follow`.** A Flutter client must derive
the pending diff card from `tool/call.data.arguments` itself; the applied card comes from
`tool/result.data.meta.diffs`.

Full literal `turn/end`:
```json
{ "type": "turn/end", "seq": 12, "time": 1737000002000, "data": { "turn": 1, "reason": { "kind": "completed" } } }
```
**[VERIFIED]** `reason` is the `TurnEndReason` union. Its exact member literals are declared in the
session package; one concrete literal from the repair path is
`{ kind: 'interrupted' }` (`packages/core/session/src/repair.ts:133`). **[AMBIGUOUS]** I did not
enumerate the full `TurnEndReason` union in this pass — the Flutter client should treat `reason` as
an object with a `kind` string and not hard-fail on unknown members.

##### `surfaceOp` and `sourceEventSeqs`

(`packages/api/session-controller/src/types.ts:414-417`)

```ts
export type SessionWireSurfaceOp =
  | 'append'
  | { readonly op: 'replace'; readonly startSeq: number; readonly endSeq: number }
```

**[VERIFIED]** Required on surface events (`system/message`, `user/message`, `assistant/message`,
`tool/result`, `packages/core/session/src/types.ts:417-421`), absent on log-only events.
`sourceEventSeqs` cites replaced surface nodes.

#### 4.2.3 `assistant-stream` — transient live chunks

Frame union (`packages/api/session-controller/src/types.ts:475-506`):

```ts
export type SessionAssistantStreamFrame =
  | {
    readonly type: 'start'
    readonly attemptId: LlmAttemptId
    readonly revision: number
    readonly startedAfterSeq: SessionSeqCursor
    readonly turn: number
    readonly step: number
  }
  | {
    readonly type: 'chunk'
    readonly attemptId: LlmAttemptId
    readonly revision: number
    readonly index: number
    readonly time: number
    readonly chunk: JsonValue
  }
  | {
    readonly type: 'end'
    readonly attemptId: LlmAttemptId
    readonly revision: number
    /** Number of chunk frames represented by this terminal marker. */
    readonly index: number
    readonly outcome:
      | {
        readonly kind: 'committed'
        readonly eventType: 'assistant/message' | 'assistant/attempt'
        readonly seq: number
      }
      | { readonly kind: 'abandoned' }
  }
```

Literal frames (verbatim test fixtures,
`packages/api/session-controller/tests/sessions-service.client.spec.ts:185-216`):

```json
{ "type": "assistant-stream", "frame": {
  "type": "start", "attemptId": "web-live-attempt", "revision": 1,
  "startedAfterSeq": -1, "turn": 1, "step": 1 } }
```
```json
{ "type": "assistant-stream", "frame": {
  "type": "chunk", "attemptId": "web-live-attempt", "revision": 2, "index": 0,
  "time": 1, "chunk": { "type": "text-delta", "index": 0, "text": "live" } } }
```
```json
{ "type": "assistant-stream", "frame": {
  "type": "end", "attemptId": "web-live-attempt", "revision": 3, "index": 1,
  "outcome": { "kind": "committed", "eventType": "assistant/message", "seq": 0 } } }
```

**[VERIFIED]** `revision` is strictly dense: `revision_expected = previous_revision + 1`. The
client transport enforces it (`packages/api/session-controller/src/client/transport.ts:206-214`):

```ts
if (frame.type === 'assistant-stream') {
  const expected = (assistantRevision ?? 0) + 1
  if (frame.frame.revision !== expected) {
    throw new RemoteStreamCarrierError(
      `session assistant stream skipped revision ${String(expected)}`,
    )
  }
  assistantRevision = frame.frame.revision
  yield { type: 'notification', notification: frame.frame }
```

`index` is the dense 0-based chunk counter within the attempt. The accumulated baseline
(`packages/api/session-controller/src/assistant-stream.ts:84-101`) exposes `nextIndex` and a
compact `stream` array of `AssistantStreamRecord` (`packages/llm/llm/src/assistant-stream.ts:20-44`):

```ts
export type AssistantStreamRecord =
  | { readonly type: 'text-chunks'; readonly time0: number; readonly index: number
      readonly dt: readonly number[]; readonly texts: readonly string[] }
  | { readonly type: 'reasoning-chunks'; readonly time0: number; readonly index: number
      readonly dt: readonly number[]; readonly texts: readonly string[] }
  | { readonly type: 'tool-call-chunks'; readonly time0: number; readonly index: number
      readonly dt: readonly number[]; readonly id: ToolCallId; readonly name?: string
      readonly args: readonly string[] }
  | { readonly type: 'chunk'; readonly time: number; readonly chunk: StreamChunk }
```

End-to-end ordering (real test, `packages/api/session-controller/tests/session-history-journal.host.spec.ts:225-233`):

```ts
await expect(iterator.next()).resolves.toEqual({
  done: false, value: { type: 'assistant-stream', frame: nextFrame },
})
await expect(iterator.next()).resolves.toEqual({
  done: false, value: { type: 'event', event: message },
})
await expect(iterator.next()).resolves.toEqual({
  done: false, value: { type: 'assistant-stream', frame: endFrame },
})
```

**[VERIFIED]** The durable `assistant/message` arrives BETWEEN `chunk` frames and the `end` marker.
`startedAfterSeq` (present only on `start`) is `cursorBeforeNext(session.seq)`
(`packages/api/session-controller/src/history.ts:60`, `:278-280`).

### 4.3 A second, related endpoint: `session/page`

Not a stream. `@Remote('page')` (`packages/api/session-controller/src/index.ts:388-391`).
Request `SessionPageRequest` = `{ address, throughSeq, beforeSeq?, maxMessages? }`
(`types.ts:439-446`); response `SessionPage` = `{ records, hasMore }` (`types.ts:508-512`).
Used by the client to page backwards, and — importantly — the `throughSeq` it passes is the
`cursor` read from the `session/follow` opening snapshot. Test evidence:
`apps/web/tests/smoke-real.e2e.ts:111-194`.

---

## 5. The `session/control` logical stream

### 5.1 Is it real and supported?

**[VERIFIED] YES.** It is a real Host stream, opened unconditionally by the client at apply time.

Host registration (`packages/api/session-controller/src/index.ts:405-413`):

```ts
/**
 * Stream a complete live-control baseline followed by replacement frames.
 * @param signal - cancellation owned by the Remote stream carrier.
 * @returns one complete baseline followed by live replacement frames.
 */
@Remote({ mode: 'stream' })
control(signal: AbortSignal): AsyncIterable<SessionControlFrame> {
  return this.controlState.control(signal)
}
```

Client opens it once (`packages/api/session-controller/src/client/index.ts:114-118`):

```ts
const control = createSessionControlStream(remotes, {
  accept: (frame) => { sessions.handleControlFrame(frame) },
  failed: (error) => { console.error('[session-controller] control stream failed:', error) },
})
control.start()
```

And `createSessionControlStream` (`packages/api/session-controller/src/client/transport.ts:119-126`)
opens via `remote.session.control(signal)` — a **zero-business-argument** stream.

### 5.2 Exact opening message

```jsonc
{
  "type": "open",
  "streamId": "control-1",
  "endpoint": "session/control",
  "payload": { "args": {} }
}
```

**[VERIFIED]** `control(signal)` has NO business parameters, only the trailing `signal`
(`packages/api/session-controller/src/index.ts:410-413`). The args object must therefore be empty
`{}` — recall `assertExactArguments` rejects extra keys and `remoteRequest` requires `args` present
and a plain object (`packages/api/gateway/src/index.ts:942-951`, `:1107-1119`).

Cross-check: the test-mock dispatch passes no positional arguments for this stream —
`apps/web/tests/assembled-remote.ts:162` `mock.stream('session/control', (_args, stream) => {…})`
with `remote-default-responses.ts:43` supplying only the opening frame.

### 5.3 Downlink frames

**Exact frame `type` strings: `baseline`, `queue`, `jobs`, `projection`.** The question's guess was
correct, with `projection` singular.

`packages/api/session-controller/src/types.ts:567-572`:

```ts
/** Host-wide live state stream. Each generation starts with exactly one baseline. */
export type SessionControlFrame =
  | { readonly type: 'baseline'; readonly value: SessionControlBaseline }
  | { readonly type: 'queue'; readonly sessionId: SessionId; readonly items: readonly SessionQueuedItem[] }
  | { readonly type: 'jobs'; readonly sessionId: SessionId; readonly jobs: readonly SessionJob[] }
  | ({ readonly type: 'projection' } & SessionProjectionUpdate)
```

Note the shapes differ: `baseline` nests its payload under **`value`**, while `queue`, `jobs` and
`projection` spread their fields at the TOP level of the frame. This is a common client bug source.

Emission (`packages/api/session-controller/src/control.ts:61-72`):

```ts
async *control(signal: AbortSignal): AsyncIterable<SessionControlFrame> {
  signal.throwIfAborted()
  const queue = new ControlQueue()
  this.streams.add(queue)
  try {
    yield { type: 'baseline', value: this.baseline() }
    yield* queue.iterate(signal)
  } finally {
    this.streams.delete(queue)
    queue.end()
  }
}
```

**[VERIFIED]** Exactly one `baseline` first, then replacement frames, forever.

#### `baseline`

```json
{
  "type": "baseline",
  "value": {
    "queues": {
      "session-1": [
        {
          "id": "message-9",
          "placement": "queued",
          "rpcId": "req-abc",
          "message": { "id": "message-9", "content": [{ "type": "text", "text": "next" }] }
        }
      ]
    },
    "jobs": {
      "session-1": [
        { "id": "job-1", "kind": "shell", "label": "npm test", "status": "running",
          "detail": "…", "startedAt": 1737000000000, "finishedAt": 1737000009000 }
      ]
    },
    "projections": {
      "session-1": { "asOfSeq": 12, "values": {} }
    }
  }
}
```

Literal (the canonical empty baseline, repeated across the test suite —
`packages/api/session-controller/tests/client-apply.client.spec.ts:21`):

```ts
const BASELINE = { type: 'baseline', value: { queues: {}, jobs: {}, projections: {} } }
```

Types:

- `SessionControlBaseline` (`types.ts:552-557`):
  ```ts
  export interface SessionControlBaseline {
    readonly queues: Readonly<Record<SessionId, readonly SessionQueuedItem[]>>
    readonly jobs: Readonly<Record<SessionId, readonly SessionJob[]>>
    readonly projections: Readonly<Record<SessionId, SessionProjectionBaseline>>
  }
  ```
- `SessionQueuedItem` (`types.ts:528-539`):
  ```ts
  export interface SessionQueuedItem {
    readonly id: MessageId
    readonly placement: 'queued' | 'steering' | 'context'
    readonly rpcId?: SessionRequestId
    readonly message: { readonly id: MessageId; readonly content: readonly JsonValue[] }
  }
  ```
- `SessionJob` (`types.ts:541-550`):
  ```ts
  export interface SessionJob {
    readonly id: JobId
    readonly kind: string
    readonly label: string
    readonly status: 'running' | 'stopping' | 'completed' | 'killed' | 'failed'
    readonly detail?: string
    readonly startedAt: number
    readonly finishedAt?: number
  }
  ```

**[VERIFIED]** `placement` mapping (`packages/api/session-controller/src/control.ts:177-192`):
`nextTurn` → `'queued'`; `nextStep` from a user source → `'steering'`; `nextStep` otherwise →
`'context'`. `rpcId` is present only when the queued user message carries a `user` source with an
`rpcId` (`:194-198`) — that is the client-minted `requestId` from `session/prompt`
(`types.ts:377-382`), used to retire the optimistic echo.

#### `queue`

```json
{
  "type": "queue",
  "sessionId": "session-1",
  "items": [
    { "id": "message-9", "placement": "queued", "rpcId": "req-abc",
      "message": { "id": "message-9", "content": [{ "type": "text", "text": "next" }] } }
  ]
}
```

Broadcast on inbox projection change (`packages/api/session-controller/src/control.ts:34-41`):

```ts
if (key !== 'inbox') return
const agent = this.ctx.agents.get(session.id)
if (agent?.session !== session) return
this.broadcast({
  type: 'queue',
  sessionId: session.id,
  items: queueItemsFromInbox(value as InboxState),
})
```

**[VERIFIED]** `items` is the COMPLETE replacement set for that session, not a delta.

#### `jobs`

```json
{
  "type": "jobs",
  "sessionId": "session-1",
  "jobs": [
    { "id": "job-1", "kind": "shell", "label": "npm test", "status": "running",
      "startedAt": 1737000000000 }
  ]
}
```

Broadcast points (`packages/api/session-controller/src/control.ts:43-49`, `:105-117`): on
`jobs.onJobsChanged(owner)` for the owning agent, or for EVERY session when the owner is
`undefined`. `jobView` (`:200-209`) omits `detail`/`finishedAt` when the source has none.

#### `projection`

```json
{ "type": "projection", "sessionId": "session-1", "key": "inbox", "value": {…}, "seq": 12 }
```

`SessionProjectionUpdate` (`types.ts:559-565`):

```ts
export interface SessionProjectionUpdate {
  readonly sessionId: SessionId
  readonly key: string
  readonly value: JsonValue
  readonly seq: number
}
```

Broadcast (`packages/api/session-controller/src/control.ts:26-33`):

```ts
ctx.sessionProjections.onChanged((session, key, value, seq) => {
  this.broadcast({
    type: 'projection',
    sessionId: session.id,
    key,
    value: value as JsonValue,
    seq,
  })
  …
})
```

**[VERIFIED]** `projection` is per-key replacement, not a whole-session snapshot. Known projection
keys declared by this package: `sessionListMetadata`, `imageLimits`, `modelSelection`
(`packages/api/session-controller/src/types.ts:15-32`), plus `inbox` (used at `control.ts:34`).

---

## 6. The `workspace/follow` logical stream

### 6.1 Existence and opening message

**[VERIFIED]** Endpoint string is `'workspace/follow'`
(`packages/api/workspace-controller/tests/remote/workspace.client.ts:29`):

```ts
export const FOLLOW = 'workspace/follow'
```

Host registration (`packages/api/workspace-controller/src/index.ts:128-131`):

```ts
@Remote({ mode: 'stream' })
follow(signal: AbortSignal): AsyncIterable<WorkspaceFollowFrame> {
  return this.feed.follow(signal)
}
```

Opening message (zero business args, like `session/control`):

```jsonc
{
  "type": "open",
  "streamId": "ws-1",
  "endpoint": "workspace/follow",
  "payload": { "args": {} }
}
```

Client opens it (`packages/api/workspace-controller/src/client/index.ts:79-86`) via
`remote.workspace.follow(signal)` — signal only.

### 6.2 Frames

`packages/api/workspace-controller/src/types.ts:117-133`:

```ts
/** Complete reconnect baseline for Workspace browser state. */
export interface WorkspaceBaseline {
  readonly items: readonly WorkspaceView[]
  readonly archivedSessionIds: readonly SessionId[]
}

/** One ordered Workspace change after a generation's baseline. */
export type WorkspaceFollowIncrement =
  | { readonly type: 'upsert'; readonly workspace: WorkspaceView }
  | { readonly type: 'remove'; readonly workspaceId: WorkspaceId }
  | { readonly type: 'order'; readonly workspaceIds: readonly WorkspaceId[] }
  | { readonly type: 'archived'; readonly archivedSessionIds: readonly SessionId[] }

/** Workspace state stream; every generation starts with exactly one baseline. */
export type WorkspaceFollowFrame =
  | { readonly type: 'baseline'; readonly value: WorkspaceBaseline }
  | WorkspaceFollowIncrement
```

**[VERIFIED]** The question's list `baseline/upsert/remove/order/archived` is exactly right. As
with `session/control`, `baseline` nests under **`value`**; the four increments do NOT.

`WorkspaceView` (`packages/api/workspace-controller/src/types.ts:14-27`):

```ts
export interface WorkspaceView {
  readonly workspaceId: WorkspaceId
  /** Canonical host directory path. */
  readonly path: string
  /** User-visible title. */
  readonly title: string
  /** Sessions accounted to this Workspace in manual order. */
  readonly sessionIds: readonly SessionId[]
  /** ISO-8601 creation instant. */
  readonly createdAt: string
  /** ISO-8601 last-mutation instant. */
  readonly updatedAt: string
}
```

**[VERIFIED]** `createdAt`/`updatedAt` are **ISO-8601 strings**, unlike `session/*` timestamps which
are epoch milliseconds. Do not mix these up.

Literal frames:

```json
{ "type": "baseline",
  "value": {
    "items": [
      { "workspaceId": "ws-1", "path": "D:\\work\\alpha", "title": "alpha",
        "sessionIds": ["session-1"],
        "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z" }
    ],
    "archivedSessionIds": []
  } }
```
```json
{ "type": "upsert",
  "workspace": { "workspaceId": "ws-2", "path": "D:\\work\\beta", "title": "beta",
                 "sessionIds": [], "createdAt": "2026-01-02T00:00:00.000Z",
                 "updatedAt": "2026-01-02T00:00:00.000Z" } }
```
```json
{ "type": "remove", "workspaceId": "ws-2" }
```
```json
{ "type": "order", "workspaceIds": ["ws-2", "ws-1"] }
```
```json
{ "type": "archived", "archivedSessionIds": ["session-7"] }
```

The empty baseline, verbatim (`packages/test-support/client-runtime/src/assembly/remote-default-responses.ts:45`):

```ts
'workspace/follow': openStream([{ type: 'baseline', value: { items: [], archivedSessionIds: [] } }]),
```

And the builder (`packages/api/workspace-controller/tests/remote/workspace.client.ts:66-68`):

```ts
export function baseline(...ids: readonly string[]): WorkspaceBaselineFrame {
  return { type: 'baseline', value: { items: ids.map(id => workspace(id)), archivedSessionIds: [] } }
}
```

**[VERIFIED]** Emission order within one `domain/changed` for table `''`
(`packages/api/workspace-controller/src/feed.ts:95-131`): all new `upsert` frames, then possibly
one `order`, then possibly one `archived`. Deleted rows emit `remove`. Both `order` and `archived`
carry COMPLETE replacement sets.

---

## 7. The `cancel` client message

**[VERIFIED] Yes — `{type:'cancel', streamId}` exists and is the only way to close a logical stream
without closing the socket.**

Definition (`packages/api/gateway/src/stream-protocol.ts:250`):

```ts
| { readonly type: 'cancel'; readonly streamId: string }
```

Host handling (`packages/api/gateway/src/stream-server.ts:134-139`):

```ts
private receive(text: string): void {
  const message = parseRemoteStreamClientMessage(text)
  if (message.type === 'cancel') {
    this.streams.get(message.streamId)?.abort.abort(new Error('Remote stream cancelled'))
    return
  }
  if (this.streams.has(message.streamId)) {
    throw new Error(`api gateway: duplicate Remote stream id ${JSON.stringify(message.streamId)}`)
  }
  …
}
```

Semantics — **[VERIFIED]**:

1. Cancelling an UNKNOWN `streamId` is a silent no-op (`?.abort` on `undefined`), not an error.
2. Cancelling a live stream aborts the Host-side async iterator with reason
   `Error('Remote stream cancelled')`. The `finally` blocks run (`service.returns` increments).
3. **No `end` and no `error` frame is sent** for the cancelled stream — `pump`'s
   `!active.abort.signal.aborted` guards suppress both (`stream-server.ts:166`, `:168`).
4. The socket stays OPEN and every other logical stream is unaffected.

Literal transcript proving all of the above
(`packages/api/gateway/tests/gateway-stream.host.spec.ts:321-335`):

```ts
sendOpen(socket, 'a', 'feed/follow', { label: 'a' })
sendOpen(socket, 'b', 'feed/follow', { label: 'b' })
await vi.waitFor(() => {
  expect(frames).toEqual(expect.arrayContaining([
    { type: 'item', streamId: 'a', value: 'a:ready' },
    { type: 'item', streamId: 'b', value: 'b:ready' },
  ]))
})
expect(service.signals.map(signal => signal.aborted)).toEqual([false, false])
expect(service.returns).toBe(0)

socket.send(JSON.stringify({ type: 'cancel', streamId: 'a' }))
await vi.waitFor(() => { expect(service.returns).toBe(1) })
expect(service.signals[0]?.aborted).toBe(true)
expect(service.signals[1]?.aborted).toBe(false)
```

**[VERIFIED — Flutter client action item]** Because no terminal frame follows a `cancel`, a client
that waits for `end`/`error` after cancelling will hang. Close the local stream state at the moment
you send `cancel`.

Closing the whole socket aborts every stream
(`packages/api/gateway/src/stream-server.ts:128-132`):

```ts
await closed
const active = [...this.streams.values()]
for (const stream of active) stream.abort.abort(new Error('Remote stream socket closed'))
await Promise.all(active.map(stream => stream.done))
```

---

## 8. HTTP endpoints

### 8.1 Common envelope

**[VERIFIED]** Every business RPC is a `POST /api/<namespace>/<method>` with the SAME envelope
shape as `$events/result` (§3). Canonical client implementation
(`packages/client/connection/src/client/rpc.ts:34-60`):

```ts
async call(channel, endpoint, payload, signal) {
  assertTarget(channel, endpoint)
  const rpcId = RpcId(randomUuid())
  const message: ClientRequest = {
    type: 'client-request',
    rpcId,
    method: endpoint,
    payload,
  }
  const response = await send(
    new URL(`${channel}/${endpoint}`, resolveBase()),
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(message),
      ...signal === undefined ? {} : { signal },
    },
  )
  if (!response.ok) {
    throw new Error(`transport failure for ${channel}/${endpoint}: HTTP ${response.status}`)
  }
  const full = parseConnectionResponse(await response.json())
  if (full.rpcId !== rpcId) {
    throw new Error(`rpcId mismatch for ${endpoint}: sent ${rpcId}, got ${full.rpcId}`)
  }
  return full.result
},
```

**Request:**
```jsonc
{
  "type": "client-request",
  "rpcId": "<client-minted unique string>",
  "method": "<same as the path's endpoint>",
  "payload": { "args": { /* endpoint fields */ } }
}
```

**Response (HTTP 200 for BOTH success and logical failure):**
```jsonc
// success
{ "type": "server-response", "rpcId": "<echoed>", "result": { "ok": true, "value": { … } } }
// logical failure
{ "type": "server-response", "rpcId": "<echoed>", "result": { "ok": false,
  "error": { "code": "session/…", "message": "…", "details": { … } } } }
```

**[VERIFIED — client bug candidate]** Success is `result.ok === true` and the business payload is
`result.value`. It is **NOT** `result.ok` mirroring the business value, and there is no extra
nesting. Error envelope's `details` is always an object (possibly `{}`), never `null`
(`packages/client/connection/src/rpc-schema.ts:10-14`).

Real HTTP transcript (`apps/web/tests/smoke-real.e2e.ts:91-109`):

```ts
const response = await fetch(`${authenticated.origin}/api/${endpoint}`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', cookie: authenticated.cookie },
  body: JSON.stringify({
    type: 'client-request',
    rpcId: `smoke-${endpoint}`,
    method: endpoint,
    payload: { args },
  }),
})
if (!response.ok) throw new Error(`${endpoint} failed over HTTP ${response.status}: ${await response.text()}`)
const body = await response.json() as {
  result: { ok: true; value: T } | { ok: false; error: { code: string; message: string } }
}
if (!body.result.ok) throw new Error(`${endpoint} failed: ${body.result.error.code}: ${body.result.error.message}`)
return body.result.value
```

Namespacing **[VERIFIED]** — the endpoint string is always `<namespace>/<method>`, exactly two
segments. If a method's first business parameter is an object literal, its wire name is the
parameter name (usually `request`), not `args`. So the `payload` is
`{ args: { request: {…} } }` when the signature is `method(request)`, versus
`{ args: {…} }` when the signature has several flat parameters.

### 8.2 Session endpoints

Source: `packages/api/session-controller/src/index.ts:223-403` and `src/types.ts:243-359`.

| Operation | Method + Path | `args` (request) | `value` (success) |
|---|---|---|---|
| List sessions | `POST /api/session/list` | `{ "_request": {} }` or `{}` | `{ "items": [SessionSummary] }` |
| Create session | `POST /api/session/create` | `{ "request": { "workspaceId"?, "cwd"?, "sessionId"?, "agentPreset"? } }` | `{ "sessionId": "…", "agentPreset"?: "…" }` |
| Send prompt | `POST /api/session/prompt` | `{ "request": { "requestId", "sessionId", "mode", "content": [...], "clientTimeZone"? } }` | `{ "accepted": true }` |
| Cancel / stop | `POST /api/session/cancel` | `{ "request": { "sessionId": "…" } }` | `{ "accepted": true }` |
| Session status | *(no such endpoint — see below)* | — | — |
| Rename | `POST /api/session/rename` | `{ "request": { "sessionId", "title" } }` | `{ "title": "…", "seq": 0 }` |
| Fork | `POST /api/session/fork` | `{ "request": { "sessionId", "atSeq"? } }` | `{ "sessionId": "…" }` |
| History page | `POST /api/session/page` | `{ "request": { "address", "throughSeq", "beforeSeq"?, "maxMessages"? } }` | `{ "records": [...], "hasMore": bool }` |
| Search | `POST /api/session/search` | `{ "request": { "query": "…" } }` | `{ "items": [{ "sessionId", "snippet" }], "hasMore": bool }` |
| Queue mutation | `POST /api/session/updateQueue` | `{ "request": { "sessionId", "itemId", "action" } }` | `{ "accepted": true }` |
| Select model | `POST /api/session/selectModel` | `{ "request": { "sessionId", "provider", "model", "reasoningEffort"? } }` | `{ "selected": ModelSelection }` |
| Model catalog | `POST /api/session/modelCatalog` | `{}` | `ModelCatalog` |

Detailed evidence:

**List** — `index.ts:223-226`:
```ts
@Remote('list')
async list(_request: SessionListRequest, signal: AbortSignal): Promise<SessionListValue> {
  return { items: await this.listState.list(signal) }
}
```
The parameter is named `_request`, but the wire name is `_request` only if the generator preserves
the leading underscore — and semantically the request is "reserved empty". **Real usage in the
codebase uses BOTH forms.** `apps/web/tests/smoke-real.e2e.ts:755-766` sends `{ _request: {} }`;
`packages/api/session-controller/src/client/sessions/manager.ts:463` calls
`this.remote.session.list({})`. And `apps/web/tests/agent-preset-selection.e2e.ts:190-192` sends:
```ts
type: 'client-request', rpcId: 'agent-preset-live', method: 'session/list',
payload: { args: { _request: {} } },
```
**[VERIFIED]** `SessionListRequest` has one optional field `cursor?` (`types.ts:243-246`). Since
`assertExactArguments` permits an omitted JSON field but rejects extra keys
(`packages/api/gateway/src/index.ts:1112-1119`), **sending `{"args":{}}` is the safest form** — it
matches every observed call and cannot be an unknown extra key. **[AMBIGUOUS]** I could not
determine from a passing test whether `_request` is accepted as a wire field name or is silently
dropped; the generated client is authoritative and I did not read the generator output. Use
`{"args":{}}`.

Literal request (`apps/web/tests/agent-preset-selection.e2e.ts:186-193`):
```json
{"type":"client-request","rpcId":"agent-preset-live","method":"session/list","payload":{"args":{"_request":{}}}}
```

Literal response items (`packages/api/session-controller/src/types.ts:162-172`):
```ts
export interface SessionSummary {
  readonly sessionId: SessionId
  readonly updatedAt: number
  readonly running: boolean
  readonly blank: boolean
  readonly parentSessionId?: SessionId
  readonly origin?: 'subagent'
  readonly cwd?: string
  readonly projections?: SessionProjectionHints
}
```
```json
{"type":"server-response","rpcId":"agent-preset-live","result":{"ok":true,"value":{
  "items":[{"sessionId":"session-1","updatedAt":1737000000000,"running":false,"blank":true,
            "cwd":"D:\\work\\alpha",
            "projections":{"asOfSeq":12,"values":{"agentPreset":"default"}}}]}}}
```
`SessionProjectionHints` = `{ asOfSeq: number, values: SessionProjectionValues }`
(`types.ts:52-57`).

**Create** — `index.ts:244-247`; request `SessionCreateRequest` (`types.ts:264-270`) all-optional:
```json
{"type":"client-request","rpcId":"create-1","method":"session/create","payload":{"args":{"request":{}}}}
```
→ `{"result":{"ok":true,"value":{"sessionId":"session-2"}}}`

Real usage: `apps/web/tests/smoke-real.e2e.ts:452` → `remoteRpc(baseUrl, 'session/create', { request: {} })`.
Also `apps/web/tests/shipped-composition.e2e.ts:735`, `:841`.

**Prompt** — `index.ts:346-350`; request `SessionPromptRequest` (`types.ts:311-320`):
```ts
export interface SessionPromptRequest {
  readonly requestId: SessionRequestId
  readonly sessionId: SessionId
  readonly mode: 'queue' | 'steer'
  readonly content: readonly PromptContentPart[]
  readonly clientTimeZone?: string
}
```
`PromptContentPart` (`types.ts:75-83`):
```ts
export type PromptContentPart =
  | { readonly type: 'text'; readonly text: string }
  | { readonly type: 'image'; readonly mediaType: ImageMediaType; readonly data: string; readonly name?: string }
  | { readonly type: 'file'; readonly receiptId: Branded<'file-upload-receipt-id'> }
```

Real literal request (`apps/web/tests/smoke-real.e2e.ts:453-458`):
```ts
await remoteRpc<{ accepted: true }>(baseUrl, 'session/prompt', { request: {
  requestId: randomUUID(),
  sessionId: created.sessionId,
  mode: 'queue',
  content: [{ type: 'text', text: 'go' }],
} })
```
→ `{"result":{"ok":true,"value":{"accepted":true}}}`

**[VERIFIED]** `requestId` is client-minted. It is persisted on the accepted user message's source
as `rpcId` (`types.ts:377-382`) and echoed back on the `session/control` `queue` frame's `rpcId`
field and on the `$events` `api-session/added`/`session/follow` `user/message` source. Flutter must
use this to retire its optimistic bubble.

**Cancel** — `index.ts:377-380`; request `SessionCancelRequest` (`types.ts:351-354`):
```json
{"type":"client-request","rpcId":"cancel-1","method":"session/cancel","payload":{"args":{"request":{"sessionId":"session-1"}}}}
```
→ `{"result":{"ok":true,"value":{"accepted":true}}}`

Confirmed to be the real stop path in the UI
(`apps/web/tests/subagent-interrupt-ui.e2e.ts:244`, `:314` both assert against
`'/api/session/cancel'`).

**Session status does NOT exist as an endpoint.** **[VERIFIED]** A repo-wide grep for
`'session/status'` finds no such Remote method; the only hits are `terminal-*` package hits for an
unrelated terminal session object. Running state is delivered two other ways:

1. `SessionSummary.running` from `POST /api/session/list` (`types.ts:166`).
2. Live push on the `$events` stream — event `"api-session/status"` with `args: [sessionId, running]`
   (`packages/api/session-controller/src/types.ts:588-594`, forwarded via the allowlist at
   `packages/api/remotes/src/remote-events.ts:24`).

Literal `emit` for it (`packages/api/session-controller/tests/client-apply.client.spec.ts:59`):
```ts
await emit(mock, 'api-session/status', sid('session-1'), true)
```
→
```json
{"type":"item","streamId":"events","value":{"type":"emit","event":"api-session/status","args":["session-1",true]}}
```

The full live-status event set on `$events` (`packages/api/session-controller/src/types.ts:574-609`):

| event | args |
|---|---|
| `api-session/added` | `[summary: SessionSummary]` |
| `api-session/removed` | `[sessionId]` |
| `api-session/status` | `[sessionId, running: boolean]` |
| `api-session/activity` | `[sessionId, updatedAt: number]` |
| `api-session/error` | `[sessionId, message: string]` |

Real `api-session/added` literal (`packages/api/session-controller/tests/client-apply.client.spec.ts:54`):
```json
{"type":"item","streamId":"events","value":{"type":"emit","event":"api-session/added",
 "args":[{"sessionId":"session-1","updatedAt":1,"running":false,"blank":true}]}}
```

### 8.3 Workspace endpoints

Source: `packages/api/workspace-controller/src/index.ts:58-131`, `src/types.ts:52-115`.
Namespace is `workspace` (`packages/api/workspace-controller/src/index.ts:43`:
`super(ctx, 'workspaceController', { namespace: 'workspace' })`).

| Operation | Method + Path | `args` (request) | `value` (success) |
|---|---|---|---|
| List workspaces | **via `workspace/follow`** — see below | — | — |
| Create / adopt | `POST /api/workspace/create` | `{ "request": { "path": "…" } }` | `{ "workspace": WorkspaceView, "created": bool }` |
| Rename | `POST /api/workspace/rename` | `{ "request": { "workspaceId", "title" } }` | `{ "workspace": WorkspaceView }` |
| Delete | `POST /api/workspace/delete` | `{ "request": { "workspaceId" } }` | `{ "deleted": true }` |
| Reorder | `POST /api/workspace/insertBefore` | `{ "request": { "workspaceId", "beforeWorkspaceId"? } }` | `{ "workspaceIds": [...] }` |
| Move session | `POST /api/workspace/insertSessionBefore` | `{ "request": { "workspaceId", "sessionId", "beforeSessionId"? } }` | `{ "workspace": WorkspaceView }` |
| Archive a session | `POST /api/workspace/archiveSession` | `{ "request": { "sessionId" } }` | `{ "archivedSessionIds": [...] }` |
| Unarchive a session | `POST /api/workspace/unarchiveSession` | `{ "request": { "sessionId" } }` | `{ "archivedSessionIds": [...] }` |

**[VERIFIED — important gap]** There is **NO `workspace/list` unary endpoint.** The Workspace
registry is conveyed exclusively by the `workspace/follow` stream's opening `baseline` frame.
Confirmation: `packages/api/workspace-controller/src/types.ts` declares no list request/value type;
`src/index.ts` declares `@Remote` on `create`, `rename`, `delete`, `insertBefore`,
`insertSessionBefore`, `archiveSession`, `unarchiveSession`, and the stream `follow` — nothing else.
The client's `WorkspaceSnapshot` is built purely from the stream
(`packages/api/workspace-controller/src/client/model.ts:29-36`, `:79-81`).

Literal archive request (mirrors `apps/web/tests/assembled-remote.ts:99`):
```json
{"type":"client-request","rpcId":"arch-1","method":"workspace/archiveSession",
 "payload":{"args":{"request":{"sessionId":"session-7"}}}}
```
→
```json
{"type":"server-response","rpcId":"arch-1","result":{"ok":true,"value":{"archivedSessionIds":["session-7"]}}}
```

**[VERIFIED]** `archiveSession`/`unarchiveSession` return the COMPLETE resulting archive set, not a
delta (`types.ts:112-115`, `:107-110`).

Create value literal (`packages/api/workspace-controller/tests/remote/workspace.client.ts:88-90`):
```json
{"workspace":{"workspaceId":"created","path":"D:\\work\\alpha","title":"created",
  "sessionIds":[],"createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},
 "created":true}
```

**[VERIFIED]** A `workspace/create` on an already-registered path is idempotent and returns the
existing row with `created: false` (`apps/web/tests/assembled-remote.ts:207-211`).

`WorkspaceAction` values are declared as `RemoteErrorDetailsMap` entries
(`packages/api/workspace-controller/src/types.ts:29-50`): `workspace/invalid-path`,
`workspace/name-conflict`, `workspace/move-invalid`, `directory-picker/unavailable`,
`directory-picker/unreadable`, `directory-picker/exists`, `directory-picker/create-failed`.

### 8.4 `$events/result`

Covered in §3. `POST /api/$events/result`.

---

## 9. Cross-cutting conventions the Flutter client must respect

1. **Two-level wrapping.** Every socket payload is `{type, streamId, value}`; the `value` is the
   domain frame. Every HTTP response is `{type, rpcId, result}`; the domain payload is
   `result.value`.
2. **`baseline` nests, everything else spreads.** `session/control` and `workspace/follow` both
   put their opening payload under `value` and their increments at the frame top level.
3. **HTTP 200 ≠ success.** Always read `result.ok`.
4. **`cancel` produces no terminal frame.** Do not await `end`/`error` after cancelling.
5. **`$events` must be opened first** if you need approval/question prompts, and its `ready` frame
   must be retained: without `clientId`, `$events/result` answers
   `Remote event result identifies no active event stream`
   (`packages/api/gateway/src/index.ts:361-363`).
6. **`request` vs flat `args`.** When the Remote method's first parameter is a single object, it is
   named `request` on the wire (`session/follow`, `session/create`, `session/prompt`, …). When the
   method has zero business parameters, `args` is `{}`.
7. **`tool/call.arguments` is an unparsed JSON string.** Decode it client-side.
8. **Diffs live at `tool/result.data.meta.diffs`**, shape `{path, oldText: string|null, newText}`.
   There is no `view` field and no `tool/view` event.
9. **Timestamps differ by domain.** `session/*` uses epoch **milliseconds**; `WorkspaceView`
   uses ISO-8601 **strings**.
10. **Endpoint paths never exceed two segments** for HTTP RPC (`namespace/method`), matching the
    regexes `CHANNEL_PATTERN = /^\/[A-Za-z0-9._~-]+$/` and
    `ENDPOINT_SEGMENT_PATTERN = /^[A-Za-z0-9_$.-]+$/`
    (`packages/client/connection/src/rpc-host.ts:32-33`).

---

## 10. Summary of what I could NOT verify

- **[AMBIGUOUS]** The exact wire field name for `session/list`, i.e. whether `_request` is accepted
  or whether `{}` is required. Use `{"args":{}}` — it is the form used by the generated client
  (`packages/api/session-controller/src/client/sessions/manager.ts:463`) and cannot be an unknown
  extra key.
- **[AMBIGUOUS]** The complete member set of `TurnEndReason` (the `turn/end.data.reason` union).
  One verified member is `{ kind: 'interrupted' }` (`packages/core/session/src/repair.ts:133`).
  Treat unknown members defensively.
- **[AMBIGUOUS]** Whether `assistant/attempt` events actually reach `session/follow` in a normal
  run, versus only `assistant/message`. Both are declared in `SessionEventMap`
  (`packages/core/session/src/types.ts:321-335`) and the `assistant-stream` `end.outcome.eventType`
  union names both (`packages/api/session-controller/src/types.ts:502`), so the client must handle
  both.
- I did not read the generated Typert client (`lib/`) artifacts, so the parameter-name → wire-name
  mapping for edge cases like a leading-underscore parameter is taken from observed test payloads
  rather than from generator source.
