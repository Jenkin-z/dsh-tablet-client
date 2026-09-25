# DSH Web Client — Conversation / Streaming State Machine & Message Rendering Spec

Source of truth: `D:\software\deepseek-harness` (read-only inspection).
Legend: **[VERIFIED]** = quoted from source. **[INFERRED]** = reasoned from adjacent code, not directly stated.

---

## 0. Architecture in one paragraph

The web client is **not** a client-owned message log. The Host owns a durable, append-only,
`seq`-ordered **session journal**. The browser opens exactly one **logical follow stream** per
session and folds it into a snapshot. There is no client-side message list that gets merged with
server state; instead there is a *single ordered event window* which a set of registered
**Conversation Node definitions** (`match` / `start` / `update` / `buildViewNode`) project into
render nodes.

Three layers, in order of authority:

1. `packages/api/gateway` — transport: cursor algebra, gap repair, reconnect (`RemoteJournalStream`, `RemoteStream`).
2. `packages/api/session-controller` — per-session state machine: window, running bit, local submission echoes, assistant transient/durable fold (`Session`, `ClientAssistantStream`).
3. `packages/client/ui-conversation` + `ui-chat` + `ui-tool` — event→node assembly (`ConversationNodeAssembler`) and rendering.

---

# PART A — STREAMING / MESSAGE STATE

## 1. Local send: optimistic bubble + rpcId reconciliation

### 1.1 Yes — there is an explicit optimistic echo, inserted synchronously

`packages/api/session-controller/src/client/contract/snapshot.ts:54-71` **[VERIFIED]**:

```ts
/**
 * One local prompt-submission echo: inserted synchronously when a submission
 * begins, so the conversation can show the message before serialization,
 * transport, and durable admission complete. Client-memory only — reload and
 * reconnect rebuild the conversation from durable events alone.
 */
export interface PendingSubmission {
  /** The prompt RPC identity; the durable `user/message` source echoes it as `rpcId`. */
  readonly requestId: SessionRequestId
  /** Expected surface until the Host reports the admitted queue or durable occurrence. */
  readonly placement: PendingSubmissionPlacement
  /** Client wall-clock ms when the submission began. */
  readonly time: number
  /** Prompt text exactly as it will be sent (one text block). */
  readonly text: string
  /** Ordered image previews and durable file metadata matching the prompt attachments. */
  readonly attachments: readonly PendingSubmissionAttachment[]
}
```

Placement union, `snapshot.ts:52` **[VERIFIED]**:
```ts
export type PendingSubmissionPlacement = 'transcript' | 'queued' | 'steering'
```

### 1.2 The id scheme: a client-minted UUID is BOTH the echo id and the prompt RPC id

`session.ts:205-222` **[VERIFIED]** — note `randomUUID()` and the **synchronous** `markDirty()`:

```ts
beginSubmission(input: BeginSubmissionInput): SubmissionHandle {
  const requestId = randomUUID() as SessionRequestId
  this.pendingSubmissions = [...this.pendingSubmissions, {
    requestId,
    placement: this.running
      ? input.mode === 'steer' ? 'steering' : 'queued'
      : 'transcript',
    time: Date.now(),
    text: input.text,
    attachments: input.attachments,
  }]
  this.submissionSettlements.set(requestId, { onRetire: input.onRetire, retiring: false })
  // The blank → engaging edge flips here, ahead of prompt(): the composer
  // docks and the echo renders on the click's own frame.
  this.promptAttempted = true
  this.notifier.markDirty()
  return { requestId, abandon: () => { this.retireFailedSubmission(requestId) } }
}
```

Placement is derived from **running state at click time + delivery mode**, not from a server hint.
Test-encoded (`packages/api/session-controller/tests/session-pending-submissions.client.spec.ts:90-102`) **[VERIFIED]**:

```ts
it('derives and captures the echo placement from running state and delivery mode', async ({ mock, start }) => {
  const session = await sessionBench(mock, start, SID)
  session.beginSubmission({ mode: 'queue', text: '空闲', attachments: [] })
  session.handleRunning(true)
  session.beginSubmission({ mode: 'queue', text: '排队', attachments: [] })
  session.beginSubmission({ mode: 'steer', text: '纠偏', attachments: [] })
  session.handleRunning(false)
  expect(session.getSnapshot().pendingSubmissions.map(({ text, placement }) => ({ text, placement }))).toEqual([
    { text: '空闲', placement: 'transcript' },
    { text: '排队', placement: 'queued' },
    { text: '纠偏', placement: 'steering' },
  ])
})
```

And the identity is passed straight into the prompt RPC (`session.ts:246-255`) **[VERIFIED]**:

```ts
result = await this.remote.session.prompt({
  requestId: requestId ?? randomUUID() as SessionRequestId,
  sessionId: this.sessionId,
  mode,
  content,
  clientTimeZone,
}, signal)
```

Test (`session-pending-submissions.client.spec.ts:138-143`) **[VERIFIED]**:
```ts
it('sends the echo identity as the prompt requestId', async ({ mock, start }) => {
  ...
  expect(mock.log.requests('session/prompt')).toMatchObject([{ requestId: handle.requestId, sessionId: SID }])
})
```

> **Porting consequence:** the correlation is a **client-minted UUID round-tripped through the Host**.
> The Host echoes it back on the durable `user/message`'s `source.rpcId` and on queue occurrences'
> `rpcId`. There is **no** dedup window and **no** seq-based dedup for echoes — the id is exact.

### 1.3 The duplicate echo is reconciled at RENDER time (atomic swap, no dedup window)

Two mechanisms run in parallel, deliberately.

**(a) Snapshot retirement, delayed by one animation frame** — `session.ts:747-761` **[VERIFIED]**:

```ts
/**
 * Latch one observed settlement and remove the echo an animation frame
 * later. The delay keeps the echo in the snapshot until the frame in which
 * the durable node (whose assembly frame was registered first) is
 * renderable; the render-time rpcId dedupe hides the one-frame overlap.
 */
private scheduleObservedRetirement(
  requestId: SessionRequestId,
  attachments: readonly (ImageAttachmentRef | FileAttachmentRef)[],
): void {
  const settlement = this.submissionSettlements.get(requestId)
  if (settlement === undefined || settlement.retiring) return
  settlement.retiring = true
  scheduleFrame(() => { this.finishSubmission(requestId, { reason: 'observed', attachments }) })
}
```

`scheduleFrame` (`session.ts:827-831`) **[VERIFIED]**:
```ts
function scheduleFrame(fn: () => void): void {
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(() => { fn() })
  else setTimeout(fn, 0)
}
```

The `retiring: boolean` latch (`session.ts:125-128`) is the **exactly-once guard** — a queue frame and
its durable event cannot both retire one echo:
```ts
private readonly submissionSettlements = new Map<SessionRequestId, {
  readonly onRetire?: ((retirement: PendingSubmissionRetirement) => void) | undefined
  retiring: boolean
}>()
```

**(b) Render-time dedupe by `rpcId`** — `ui-chat/src/client/chat/ChatView.tsx:132-157` **[VERIFIED]**:

```ts
/**
 * Prompt-RPC identities already rendered by durable material: user/steering
 * node sources plus queue occurrences. A submission echo whose identity
 * appears here is hidden in the same render, so the echo→durable swap is
 * atomic — no duplicate, no gap — regardless of when the echo leaves the
 * session snapshot.
 */
function observedRpcIds(
  order: readonly string[],
  nodes: ChatSnapshot['nodes'],
  queue: readonly { readonly rpcId?: string }[],
): ReadonlySet<string> {
  const observed = new Set<string>()
  for (const key of order) {
    const node = nodes.get(key)
    if (node === undefined || (node.kind !== 'user' && node.kind !== 'steering')) continue
    const source = (node.data as { readonly source?: unknown }).source as
      | { readonly kind?: unknown; readonly rpcId?: unknown }
      | undefined
    if (source?.kind === 'user' && typeof source.rpcId === 'string') observed.add(source.rpcId)
  }
  for (const item of queue) {
    if (item.rpcId !== undefined) observed.add(item.rpcId)
  }
  return observed
}
```

Applied at `ChatView.tsx:287-297` **[VERIFIED]**:
```ts
const pendingSubmissions = useSession(s => s.pendingSubmissions)
...
const visibleSubmissions = useMemo(() => {
  if (pendingSubmissions.length === 0) return pendingSubmissions
  const observed = observedRpcIds(order, nodeStore, inbox)
  return pendingSubmissions.filter(submission => !observed.has(submission.requestId))
}, [pendingSubmissions, order, nodeStore, inbox])
```

**Test that encodes the whole contract** — `ui-chat/tests/chat-view.client.spec.tsx:1051-1086` **[VERIFIED]**:

```ts
it('renders local submission echoes at the flow tail and swaps atomically with the durable node', () => {
  const h = makeHarness(
    { nodes: [assistant(1, 'working')] },
    { pendingSubmissions: [{ requestId: 'req-1' as never, placement: 'transcript',
        time: 5_000, text: '即发即显', attachments: [] }] },
  )
  const view = render(<h.ChatView {...h.props} />)
  expect(view.getByText('即发即显').closest('[data-submission-echo]')).not.toBeNull()

  // The durable node arrives while the echo is STILL in the session
  // snapshot: the render-time rpcId dedupe keeps exactly one bubble.
  act(() => {
    h.setChat({ nodes: [ assistant(1, 'working'),
      { kind: 'user', seq: 2, time: 2_000,
        content: [{ type: 'text', text: '即发即显' }] as never,
        source: { kind: 'user', rpcId: 'req-1' } } ] })
  })
  expect(view.getAllByText('即发即显')).toHaveLength(1)
  expect(view.container.querySelector('[data-submission-echo]')).toBeNull()

  // The delayed snapshot retirement changes nothing visible.
  act(() => { h.setSession({ pendingSubmissions: [] }) })
  expect(view.getAllByText('即发即显')).toHaveLength(1)
})
```

> **Porting consequence:** the echo is removed **twice over** — once by render-time filter (immediate,
> atomic) and once a frame later in the snapshot. A Flutter port must implement the *render-time*
> filter; the snapshot delay alone would produce a visible one-frame double bubble.

### 1.4 Placement decides WHERE the echo lives

`ChatView.tsx:1126-1157` **[VERIFIED]** test — a `queued` echo never enters the Chat flow
(`expect(view.queryByText('排队中')).toBeNull()` before *and* after Host admission); queued
occurrences belong to the QueueDock. `steering` echoes render as pending steering bubbles
(`data-pending-steering`, `MessageItem.tsx:293-300`).

Failure paths retire immediately as `failed` (`session.ts:763-780`) and set `promptError`:
```ts
retireFailedSubmission(requestId: SessionRequestId): void {
  const settlement = this.submissionSettlements.get(requestId)
  if (settlement === undefined || settlement.retiring) return
  settlement.retiring = true
  this.finishSubmission(requestId, { reason: 'failed' })
}
```

Retirement union (`contract/session.ts:24-29`) **[VERIFIED]**:
```ts
export type PendingSubmissionRetirement =
  | { readonly reason: 'observed'; readonly attachments: readonly (ImageAttachmentRef | FileAttachmentRef)[] }
  | { readonly reason: 'failed' }
```

---

## 2. Streaming delta accumulation, batching, and merge-on-completion

### 2.1 There IS a separate "streaming" representation and a final one — and they are different objects

The streaming representation is **not** a message. It is a client-only event type
`assistant/live-chunk` injected into the *same* ordered event window.

`api/session-controller/src/client/contract/events.ts:6-20` **[VERIFIED]**:
```ts
/** Client-only live chunk presentation; `seq` orders the transient row between durable Session seqs. */
export interface AssistantLiveChunkEvent {
  readonly type: 'assistant/live-chunk'
  readonly seq: number
  readonly time: number
  readonly data: {
    readonly attemptId: LlmAttemptId
    readonly turn: number
    readonly step: number
    readonly chunk: StreamChunk
  }
}

/** Current durable Session event or one client-only live chunk presentation. */
export type SessionEventLike = SessionEvent | AssistantLiveChunkEvent
```

Entry wrapper (`events.ts:22-35`) **[VERIFIED]**:
```ts
export type SessionEventLikeEntry =
  | { readonly type: 'event'; readonly event: SessionEvent }
  | { readonly type: 'transient'; readonly event: AssistantLiveChunkEvent }

export type SessionLiveEventEntry = Extract<SessionEventLikeEntry, { readonly type: 'event' }>
/** Durable Assistant event that atomically supersedes one attempt's transient rows. */
export interface SessionAssistantSettlementEntry {
  readonly type: 'event'
  readonly event: SessionEvent<'assistant/message'> | SessionEvent<'assistant/attempt'>
}
export type SessionTransientEventEntry = Extract<SessionEventLikeEntry, { readonly type: 'transient' }>
```

### 2.2 Batching: **triple `requestAnimationFrame`**, per-chunk

`ui-conversation/src/client/conversation/assembly.ts:130-147` **[VERIFIED]**:

```ts
private publish(publication: ConversationPublication): void {
  if (publication === 'none') return
  if (publication === 'animation-frame' && typeof requestAnimationFrame === 'function') {
    if (this.frame !== undefined) return
    // Cross three paint opportunities before publishing high-frequency stream updates.
    this.frame = requestAnimationFrame(() => {
      this.frame = requestAnimationFrame(() => {
        this.frame = requestAnimationFrame(() => {
          this.frame = undefined
          this.flush()
        })
      })
    })
    return
  }
  this.cancelFrame()
  this.flush()
}
```

Publication ranks (`assembler.ts:54-58`) **[VERIFIED]**:
```ts
const PUBLICATION_RANK: Record<ConversationPublication, number> = {
  none: 0,
  'animation-frame': 1,
  immediate: 2,
}
```

The Assistant Step definition chooses the cadence per chunk — `ui-chat/src/client/conversation-nodes/assistant.ts:321-326` **[VERIFIED]**:

```ts
publication: (match) => {
  if (match.event.type === 'step/start') return 'none'
  if (match.event.type !== 'assistant/live-chunk') return 'immediate'
  const type = match.event.data.chunk.type
  return type === 'usage' || type === 'finish' ? 'none' : 'animation-frame'
},
```

> **Exact constants:** `3` nested rAFs (≈3 frames ≈ 50 ms @60 Hz) for streaming chunks; `0` frames
> (immediate/synchronous) for `assistant/message`, `step/start` publishes nothing, and
> `usage`/`finish` chunks publish nothing. There is **no** ms-based throttle anywhere.

The turn-tail definition uses `'immediate'` only on `turn/end` — `ui-chat/src/client/conversation-nodes/turn-tail.ts:186` **[VERIFIED]**:
```ts
publication: match => match.event.type === 'turn/end' ? 'immediate' : 'none',
```

### 2.3 The accumulator — block-level fold with reference discipline

`ui-chat/src/client/conversation-nodes/partial.ts:20-100` **[VERIFIED]**:

```ts
/** Live Assistant-frame accumulator: folds StreamChunks into AssistantBlock[] with block-level immutability. */
export class PartialAccumulator {
  // Sparse on purpose: block-start may arrive out of order, leaving holes until compaction.
  private blocks: (AssistantBlock | undefined)[] = []
  private changed = true
  private snapshot: PartialAssistant

  push(chunk: StreamChunk): boolean {
    switch (chunk.type) {
      case 'block-start': {
        this.blocks[chunk.index] = emptyAssistantBlock(chunk.blockType)
        this.changed = true
        return true
      }
      case 'text-delta': {
        const prev = this.blocks[chunk.index]
        this.blocks[chunk.index] = { kind: 'text', text: (prev?.kind === 'text' ? prev.text : '') + chunk.text }
        ...
      }
      case 'reasoning-delta': { ... }
      case 'tool-call-delta': {
        const prev = this.blocks[chunk.index]
        const base = prev?.kind === 'tool-call' ? prev : { kind: 'tool-call' as const, callId: '', name: '', argsRaw: '' }
        this.blocks[chunk.index] = {
          kind: 'tool-call',
          callId: base.callId || String(chunk.id),
          name: chunk.name ?? base.name,
          argsRaw: base.argsRaw + chunk.argumentsDelta,
        }
        ...
      }
      case 'block-end': {
        this.blocks[chunk.index] = toAssistantBlock(chunk.block)
        ...
      }
      default:
        // usage / finish / merge-extensible unknown variants: no visible block change
        // (finish is immediately followed by the assistant/message that supersedes the partial).
        return false
    }
  }

  toPartial(): PartialAssistant {
    if (this.changed) {
      // Compact sparse indexes (out-of-order block-start) into render order.
      this.snapshot = { turn: this.turn, step: this.step, blocks: this.blocks.filter((b): b is AssistantBlock => b !== undefined) }
      this.changed = false
    }
    return this.snapshot
  }
}
```

Key semantics, all test-encoded in `ui-chat/tests/partial.client.spec.ts` **[VERIFIED]**:
- `text-delta` into an empty/mismatched slot **starts from `''`** (not an error) — `:27-34`.
- `reasoning-delta` into a `text` slot **replaces** it (`换型重起`) — `:32-33`.
- `tool-call-delta`: **first id pins `callId`**, a late `name` overrides, args concatenate — `:50-57`:
  ```ts
  acc.push(chunk({ type: 'tool-call-delta', index: 0, id: 'c1', argumentsDelta: '{"a"' }))
  acc.push(chunk({ type: 'tool-call-delta', index: 0, id: 'c2-late', name: 'echo', argumentsDelta: ':1}' }))
  expect(acc.toPartial().blocks).toEqual([
    { kind: 'tool-call', callId: 'c1', name: 'echo', argsRaw: '{"a":1}' },
  ])
  ```
- `block-end` **replaces the accumulated block wholesale** — `:59-64`.
- `usage`/`finish`/unknown return `false` and keep the **same snapshot reference** — `:66-74`.
- Sparse indexes compact to dense render order — `:76-85`.

### 2.4 Merge on completion: the durable settlement *replaces* the transient rows

`ui-chat/src/client/conversation-nodes/assistant.ts:164-178` **[VERIFIED]** — the final message
wholesale-replaces the accumulated blocks:

```ts
function settleMessage(
  state: AssistantState,
  match: ConversationMatch,
  event: SessionEvent<'assistant/message'>,
): AssistantState {
  const blocks = toAssistantBlocks(event.data.message.content)
  return {
    ...state,
    blocks,
    visibleBlocks: countVisibleBlocks(blocks),
    hidden: false,
    final: match,
    usage: event.data.usage,
  }
}
```

Node status derivation (`assistant.ts:264-266`) **[VERIFIED]**:
```ts
const status = settled?.interrupted === true
  ? 'interrupted'
  : settled === undefined ? 'running' : 'settled'
```

So the client-visible assistant states are exactly `'running' | 'settled' | 'interrupted'`.
`interrupted` comes from `event.data.interrupted === true` on the durable message
(`assistant.ts:212`), or, absent a durable message, from a **synthetic** node built at a closed
step/turn boundary when `hasInterruptionEvidence(blocks)` is true (`assistant.ts:215-228`).

The window-level replacement is `MutableSessionEventSource.settleAssistant`
(`contract/events.ts:181-196`) **[VERIFIED]**:

```ts
settleAssistant(attemptId: LlmAttemptId, entry?: SessionAssistantSettlementEntry): void {
  const entries = materialize(this.window).filter(candidate => (
    candidate.type !== 'transient' || candidate.event.data.attemptId !== attemptId
  ))
  if (entry !== undefined) {
    const index = entries.findIndex(candidate => candidate.event.seq > entry.event.seq)
    if (index < 0) entries.push(entry)
    else entries.splice(index, 0, entry)
  }
  this.window = leaf(entries)
  this.publish(this.snapshot.hasMore, { kind: 'settle-assistant', attemptId, ... })
}
```

> **Merge rule:** all `transient` entries of the attempt are **dropped**, and the durable settlement
> is **inserted at its `seq` position**. There is no textual diff/merge.

---

## 3. Are BOTH `assistant-stream` frames and durable journal events consumed?

**Yes — both, and double-counting is prevented by a staged-pending + explicit-release protocol.**
(Note: the journal event the task calls `assistant/chunk` is a **format-v1/legacy** event; in the
current v3 shape the durable settlement is `assistant/message` / `assistant/attempt`, and the live
path is the `assistant-stream` **notification** with `StreamChunk` payloads.)

### 3.1 The two inputs

Transport union — `api/session-controller/src/client/transport.ts:49-58` **[VERIFIED]**:

```ts
export type SessionJournalChange =
  | { readonly type: 'replace' | 'prepend'; readonly page: SessionJournalPage
      readonly entries: readonly SessionEventLikeEntry[]; readonly hasMore: boolean }
  | { readonly type: 'append'; readonly entry: SessionLiveEventEntry }
  | { readonly type: 'assistant-stream'; readonly frame: SessionAssistantStreamFrame }
```

`notification` → `assistant-stream` mapping (`transport.ts:75-77`) **[VERIFIED]**:
```ts
case 'notification':
  return { type: 'assistant-stream', frame: change.notification }
```

### 3.2 The anti-double-count protocol — `ClientAssistantStream`

`api/session-controller/src/client/sessions/assistant-stream.ts` **[VERIFIED]**.

State (`:39-44`):
```ts
export class ClientAssistantStream {
  private activeAttempt: ActiveAttempt | undefined
  private readonly pending = new Map<number, SessionAssistantSettlementEntry>()
  private publishedSeqs = new Set<number>()
  private durableCursor = -1
  private transientInGap = 0
```

**`acceptDurable` — the durable settlement is WITHHELD, not published** (`:102-113`):
```ts
acceptDurable(entry: SessionLiveEventEntry): ClientAssistantStreamResult {
  const event = entry.event
  this.durableCursor = Math.max(this.durableCursor, event.seq)
  this.transientInGap = 0
  const settlement = assistantSettlementEntry(entry)
  if (settlement !== undefined && this.attemptForSettlement(settlement.event) !== undefined) {
    if (this.pending.has(event.seq)) return { type: 'rebaseline' }
    this.pending.set(event.seq, settlement)
    return undefined          // ← staged, NOT visible
  }
  return this.publish(entry)  // ← no matching live attempt: publish directly
}
```

`attemptForSettlement` is the **matching predicate** (`:185-195`):
```ts
private attemptForSettlement(
  event: SessionAssistantSettlementEntry['event'],
): ActiveAttempt | undefined {
  const attempt = this.activeAttempt
  if (attempt === undefined
    || (event.type === 'assistant/message' && event.surfaceOp !== 'append')
    || event.seq <= attempt.startedAfterSeq
    || attempt.turn !== event.data.turn
    || attempt.step !== event.data.step) return undefined
  return attempt
}
```

**`acceptFrame` `end` — the release** (`:160-181`):
```ts
case 'end': {
  const attempt = this.activeAttempt
  if (attempt === undefined || attempt.attemptId !== frame.attemptId) return undefined
  this.activeAttempt = undefined
  if (frame.index !== attempt.nextIndex) return { type: 'rebaseline' }
  if (frame.outcome.kind === 'abandoned') {
    return this.pending.size === 0
      ? { type: 'abandonment', attemptId: attempt.attemptId }
      : { type: 'rebaseline' }
  }
  if (this.publishedSeqs.has(frame.outcome.seq)) return undefined   // ← dedup guard
  const entry = this.pending.get(frame.outcome.seq)
  if (entry === undefined || entry.event.type !== frame.outcome.eventType) {
    return { type: 'rebaseline' }
  }
  this.pending.delete(frame.outcome.seq)
  this.publishedSeqs.add(entry.event.seq)
  return { type: 'settlement', attemptId: attempt.attemptId, entry }
}
```

**`chunk` — strict contiguous index, else full rebaseline** (`:133-159`):
```ts
case 'chunk': {
  const attempt = this.activeAttempt
  // A controller mounted after the Host saw this attempt has no start
  // frame to reconstruct. Its durable settlement publishes directly;
  // ignore the transient suffix until the next known start.
  if (attempt === undefined || attempt.attemptId !== frame.attemptId) return undefined
  if (frame.index !== attempt.nextIndex) return { type: 'rebaseline' }
  attempt.nextIndex += 1
  this.transientInGap += 1
  return { type: 'transient', entry: { type: 'transient', event: {
    type: 'assistant/live-chunk',
    seq: this.durableCursor + 1 - 1 / (this.transientInGap + 1),
    ...
  }}}
}
```

> **THE seq FABRICATION FORMULA** — transient rows are ordered **between** durable seqs by
> fractional offset: `durableCursor + 1 - 1/(transientInGap + 1)`. Always `< durableCursor + 1`
> and strictly increasing in `transientInGap`. This is how a transient sorts after all committed
> events but before the next one, without ever colliding with an integer `seq`.

`start` (`:122-132`) rejects a second start while anything is pending/in-flight:
```ts
case 'start':
  if (this.activeAttempt !== undefined || this.pending.size > 0) return { type: 'rebaseline' }
  this.pending.clear()
  this.activeAttempt = { attemptId: frame.attemptId, startedAfterSeq: frame.startedAfterSeq,
    turn: frame.turn, step: frame.step, nextIndex: 0 }
  return undefined
```

**Summary of the four non-publish outcomes** (`:26-36`) **[VERIFIED]**:
```ts
export type ClientAssistantStreamResult =
  | { readonly type: 'publish'; readonly entry: SessionLiveEventEntry }
  | { readonly type: 'settlement'; readonly attemptId: LlmAttemptId; readonly entry: SessionAssistantSettlementEntry }
  | { readonly type: 'abandonment'; readonly attemptId: LlmAttemptId }
  | { readonly type: 'transient'; readonly entry: SessionTransientEventEntry }
  | { readonly type: 'rebaseline' }
  | undefined
```

`rebaseline` → the follow stream is **restarted** (microtask, guarded) — `session.ts:677-702` **[VERIFIED]**:
```ts
private publishAssistantEntry(result: ClientAssistantStreamResult): void {
  if (result?.type === 'rebaseline') {
    const events = this.events
    queueMicrotask(() => {
      if (events !== undefined && this.events === events) events.restart()
    })
    return
  }
  if (result?.type === 'settlement') {
    this.eventSource.settleAssistant(result.attemptId, result.entry)
    ...
    return
  }
  if (result?.type === 'abandonment') {
    this.eventSource.settleAssistant(result.attemptId)   // drop transients, no durable entry
    ...
    return
  }
  if (result?.type === 'publish' && this.appendLive(result.entry)) { this.notifier.markDirty() }
  else if (result?.type === 'transient') {
    this.eventSource.append(result.entry)
    this.notifier.markDirty()
  }
}
```

> **Porting consequence (critical):** a durable settlement is only published when its matching live
> attempt's `end` frame names its `seq` **and** `eventType`. If no live attempt is open, the durable
> event publishes immediately. This is the entire double-count defense — a Flutter port must
> reproduce the `{pending, publishedSeqs, activeAttempt, durableCursor, transientInGap}` state
> machine exactly, including `rebaseline` → restart.

---

## 4. Ordering / sequencing guarantee; cursor and replay

### 4.1 `seq` is the sole ordering authority, and continuity is *enforced*, not assumed

Cursor algebra (`api/gateway/src/client/journal-stream.ts:63-74`) **[VERIFIED]**:
```ts
readonly entries: (page: Page) => readonly Entry[]
readonly hasMore: (page: Page) => boolean
readonly first: (entry: Entry) => Cursor
readonly last: (entry: Entry) => Cursor
readonly compare: (left: Cursor, right: Cursor) => number
readonly follows: (left: Cursor, right: Cursor) => boolean
```

Session binding (`api/session-controller/src/client/sessions/history-records.ts:24-35`) **[VERIFIED]** —
`first === last === event.seq`:
```ts
export function historyRecordFirstSeq(record: SessionHistoryRecord): number {
  return record.event.seq
}
export function historyRecordLastSeq(record: SessionHistoryRecord): number {
  return record.event.seq
}
```

`seq` is validated as a non-negative safe integer (`session-wire-event.ts:34-36`) **[VERIFIED]**:
```ts
const seq = event['seq']
... || typeof seq !== 'number' || !Number.isSafeInteger(seq) || seq < 0 || Object.is(seq, -0)
```

### 4.2 The three acceptance rules (`acceptEntry`, `journal-stream.ts:305-336`) **[VERIFIED]**

```ts
private async acceptEntry(entry, item, iterator): Promise<void> {
  const { first, last: cursor } = this.entryRange(entry)
  const last = this.lastCursor as Cursor
  if (this.options.compare(cursor, last) <= 0) return                     // (1) at-or-behind → silent drop
  if (this.options.compare(first, last) <= 0) {
    throw protocolViolation(`${this.options.name} emitted a partially overlapping entry`)  // (2) straddle → fatal
  }
  if (!this.options.follows(last, first)) {
    // (3) GAP → repair page, then replace the generation entirely
    const request = this.repairPageRequest()
    const superseded = await this.replaceThrough(request, cursor, item.generation, item.signal, iterator, [entry], [])
    if (superseded !== undefined) this.replaceGeneration(superseded, true)
    return
  }
  if (this.firstCursor === undefined) this.firstCursor = first
  this.lastCursor = cursor
  this.setResumeCursor(cursor)
  this.options.publish({ type: 'append', entry })
}
```

So: **duplicate `seq` → dropped (rule 1). Partial overlap → hard protocol violation (rule 2).
Hole → transparent repair (rule 3).** Ordering per entry is asserted at page level too
(`journal-stream.ts:558-560`) **[VERIFIED]**:
```ts
if (!this.options.follows(previousRange.last, range.first)) {
  throw protocolViolation(`${this.options.name} page contains discontinuous entries`)
}
```

### 4.3 There IS a cursor and a resume mechanism

`journal-stream.ts:94-100` **[VERIFIED]**:
```ts
private initialRequest!: PageRequest
private resumeCursor: Cursor | undefined
private hasResumeCursor = false
private generation = 0
private firstCursor: Cursor | undefined
private lastCursor: Cursor | undefined
```

Resume validation — a resumed cursor **behind** the last applied entry is a fatal violation
(`journal-stream.ts:269-286`) **[VERIFIED]**:
```ts
private opening(item, resumed: boolean): { readonly cursor: Cursor; readonly page: Page } {
  if (item.value.type !== 'opened') {
    throw protocolViolation(`${resumed ? 'resumed ' : ''}${this.options.name} emitted an entry before its opening cursor`)
  }
  const cursor = item.value.cursor
  if (resumed && this.lastCursor !== undefined
    && this.options.compare(cursor, this.lastCursor) < 0) {
    throw protocolViolation(
      `${this.options.name} resumed at a cursor behind the last applied entry`,
    )
  }
  this.generation = item.generation
  item.accept()
  return { cursor, page: item.value.page }
}
```

`RemoteStream` owns the physical-generation retry (`api/gateway/src/client/remote-stream.ts:39-66`)
— it reopens the logical stream across carrier generations and only `restart()`s on demand:
```ts
export class RemoteStream<Item> implements AsyncIterable<RemoteStreamItem<Item>> {
  ...
  /** Interrupt the current generation and immediately request a replacement. */
  restart(): void {
    if (this.lifetime.signal.aborted) return
    this.revision++
    this.generationAbort?.abort(new Error(`${this.options.name} generation restarted`))
  }
```

> **[INFERRED]** The connection layer (`dsh-client-connection`) owns the actual retry backoff
> timing; `RemoteStream` only performs each requested replacement. I did not read the backoff
> constants — see `packages/client/connection`.

---

## 5. Reconnect: how conversation state is rebuilt

**Answer: BOTH. A full snapshot replay of the window PLUS a delta resume from cursor, plus a
transient-prefix reconstruction.**

`Session.resync()` (`session.ts:455-470`) **[VERIFIED]**:
```ts
/** Rebuild an opened history source after address replacement.
 *  Invalidates any in-flight open first; queue state belongs to the independently
 *  reconnecting control stream and remains untouched. */
async resync(): Promise<void> {
  if (this.openState === 'cold') return
  this.openGeneration++
  const events = this.events
  this.events = undefined
  await events?.dispose()
  this.openPromise = null
  this.openState = 'cold'
  this.openError = null
  this.baseSeq = SessionLogOffset(0)
  this.notifier.markDirty()
  await this.open()
}
```

**CLEARED on resync:** `events` (disposed), `openPromise`, `openState → 'cold'`, `openError`, `baseSeq → 0`.
**PRESERVED:** the `queueMirror` ("queue state belongs to the independently reconnecting control
stream and remains untouched"), `running`, `blankBit`, `projections`, and `pendingSubmissions`
(echoes are re-observed from the fresh window — see the test at
`session-pending-submissions.client.spec.ts:215-222`).

On a replaced window, `installWindow` (`session.ts:657-675`) **[VERIFIED]**:
```ts
private installWindow(
  entries, hasMore, projections?, assistantStream?,
): void {
  // A durable gap-repair page has no assistant baseline. Clearing transient
  // attempts makes a held notification reopen follow once for an atomic
  // page/baseline pair instead of applying it to an unrelated repair cut.
  const visible = this.assistantStream.replace(entries, assistantStream)
  this.baseSeq = SessionLogOffset(entries[0]?.event.seq ?? 0)
  this.hasMore = hasMore
  if (visible.some(entry => entry.event.type === 'turn/start')) this.firstPromptPendingTurn = false
  if (projections !== undefined) this.projections.seed(projections)
  this.eventSource.replace(visible, hasMore)
  for (const entry of visible) this.observeSubmissionEvent(entry.event)
  this.notifier.markDirty()
}
```

### 5.1 The reconnect baseline reconstructs IN-FLIGHT streamed text

This is subtle and important. `ClientAssistantStream.replace` (`assistant-stream.ts:52-95`)
**[VERIFIED]**:

```ts
replace(entries, baseline?): readonly SessionEventLikeEntry[] {
  this.pending.clear()
  this.transientInGap = 0
  this.activeAttempt = undefined
  const opening = baseline?.activeAttempt
  if (opening !== undefined) {
    this.activeAttempt = { attemptId: opening.attemptId, startedAfterSeq: opening.startedAfterSeq,
      turn: opening.turn, step: opening.step, nextIndex: opening.nextIndex }
  }
  const visible: SessionEventLikeEntry[] = [...entries]
  this.publishedSeqs = new Set(visible.map(entry => entry.event.seq))
  this.durableCursor = visible.reduce((cursor, entry) => Math.max(cursor, entry.event.seq), -1)
  if (opening !== undefined) {
    for (const [index, member] of expandAssistantStream(
      opening.stream as unknown as readonly AssistantStreamRecord[],
    ).entries()) {
      this.transientInGap += 1
      visible.push({
        type: 'transient',
        event: {
          type: 'assistant/live-chunk',
          seq: this.durableCursor + 1 - 1 / (this.transientInGap + 1),
          time: member.time,
          data: { attemptId: opening.attemptId, turn: opening.turn, step: opening.step, chunk: member.chunk },
        },
      })
      if (index + 1 >= opening.nextIndex) break
    }
  }
  return visible
}
```

The Host-side accumulator that builds this baseline is
`api/session-controller/src/assistant-stream.ts` — `SessionAssistantStreamAccumulator`. It enforces
a **strict `revision` counter** (`:43-48`) **[VERIFIED]**:

```ts
accept(frame: AssistantStreamFrame, durableCursor: SessionSeqCursor): void {
  if (frame.type === 'start' && frame.revision === 1 && this.revision !== 0) {
    this.activeAttempt = undefined
    this.revision = 0
  }
  if (frame.revision !== this.revision + 1) {
    this.activeAttempt = undefined
    this.revision = frame.revision
    this.dirty = true
    return
  }
  ...
```

and drops the attempt on any id/index mismatch (`:61-72`) **[VERIFIED]**:
```ts
case 'chunk': {
  const attempt = this.activeAttempt
  if (attempt === undefined
    || attempt.attemptId !== frame.attemptId
    || frame.index !== attempt.nextIndex) {
    this.activeAttempt = undefined
    break
  }
  attempt.stream.push({ time: frame.time, chunk: frame.chunk })
  attempt.nextIndex += 1
  break
}
```

> **Porting consequence:** on reconnect the client replays the **durable window from the Host's tail
> page** AND replays the **in-flight attempt's transient chunk prefix** from the baseline, then
> resumes live frames at `nextIndex`. Partial streamed text survives a reconnect.

---

## 6. "Agent is running / idle / stopped" — derivation and exact states

### 6.1 It is a **push**, sourced from the session LIST, not from `turn/end`

Primary path is the summary/list, pushed down into live instances. `manager.ts:487-493`
**[VERIFIED]**:
```ts
// Push running/blank bits down to instantiated Sessions (the list is the authoritative summary source).
for (const s of this.summaries) {
  const session = this.sessions.get(s.sessionId)
  if (session === undefined) continue
  session.handleBlank(s.blank)
  session.handleRunning(s.running)
}
```

Live status event (`manager.ts:760-769`) **[VERIFIED]**:
```ts
/**
 * Apply one live Agent running-state change.
 * @param sessionId - Session whose Agent state changed.
 * @param running - current Agent running state.
 */
handleSessionStatus(sessionId: SessionId, running: boolean): void {
  this.recordMutation({ kind: 'status', sessionId, running })
  this.sessions.get(sessionId)?.handleRunning(running)
  this.updateCatalogActivity(sessionId, running)
}
```

Session-side setter (`session.ts:514-529`) **[VERIFIED]**:
```ts
handleRunning(running: boolean): void {
  // Turn-start conversion: a blank session never runs, so the first
  // running:true proves another side's first message landed.
  if (running && this.blankBit) {
    this.blankBit = false
    this.notifier.markDirty()
  }
  if (running) this.firstPromptPendingTurn = false
  if (this.running === running) return
  this.running = running
  this.notifier.markDirty()
}
```

**There is NO poll for running state.** `refreshList()` is a single-flight pull
(`manager.ts:452-522`), used for the **list bulk**, not for the running bit.

`turn/end` does **not** set `running = false` directly. **[INFERRED]** — the Host's Agent driver
emits the status change; the client merely relays. The only `turn/end`-driven handling is for
`turn-error` and `turn-tail` nodes (see §14), not the running bit.

### 6.2 The exact Session lifecycle state fields

`contract/snapshot.ts:73-106` **[VERIFIED]**:
```ts
/** History-open lifecycle of a Session event window. */
export type OpenState = 'cold' | 'loading' | 'open' | 'error'

/** Send/stop failure surfaced by Session consumers. */
export interface PromptError {
  readonly op: 'send' | 'stop'
  readonly error: RemoteFailure
}

/** Immutable Session lifecycle and control snapshot. */
export interface SessionSnapshot {
  readonly sessionId: SessionId
  readonly queue: readonly QueuedMessage[]
  /** Local prompt-submission echoes not yet observed as durable events or queue occurrences. */
  readonly pendingSubmissions: readonly PendingSubmission[]
  readonly running: boolean
  readonly subagent: { readonly address: SubagentAddress; readonly parentAvailable?: boolean } | null
  readonly removed: boolean
  readonly openState: OpenState
  readonly openError: RemoteFailure | null
  readonly hasMore: boolean
  readonly loadingOlder: boolean
  readonly promptError: PromptError | null
  readonly blank: boolean
  readonly lastAgentError: string | null
  /** A prompt call has begun on this Client Session object. */
  readonly promptAttempted: boolean
  /** The first accepted prompt has not reached a durable `turn/start` event. */
  readonly awaitingFirstTurn: boolean
}
```

### 6.3 The shell phase machine (3 states)

`ui-conversation/src/client/contract/snapshot.ts:17-34` **[VERIFIED]**:
```ts
/** Shell phase derived from Session lifecycle and registered target activity. */
export type ConversationPhase = 'blank' | 'engaging' | 'active'

export function conversationPhase(
  session: SessionSnapshot,
  conversation: ConversationSnapshot,
): ConversationPhase {
  const active = conversation.activeTargets.size > 0
    || (!session.blank && !session.awaitingFirstTurn)
    || session.running
  return active ? 'active' : session.promptAttempted ? 'engaging' : 'blank'
}
```

### 6.4 The layout phase machine (3 states) — `hero` / `settling` / `active`

`ui-conversation/src/client/skeleton/ConversationMainPanel.tsx:109-129` **[VERIFIED]**:
```ts
const parentAvailabilityPending = session?.subagent?.address.mode === 'continuable'
  && session.subagent.parentAvailable === undefined
const settling = sessionId !== undefined && (
  (shellPhase === 'blank' && openState === 'loading' && summaryBlank !== true)
  || parentAvailabilityPending
)
const hero = sessionId === undefined
  || (shellPhase === 'blank' && (openState === 'open' || summaryBlank === true))
const phase = settling ? 'settling' : hero ? 'hero' : 'active'
```

> **Porting consequence:** distinct user-visible conversation states are
> **`settling` (composer hidden, no flash), `hero` (blank: centered hero + workspace chip),
> `active` (normal transcript)** crossed with
> **`openState ∈ {cold, loading, open, error}`** and the header's `hideChrome`
> (`ConversationSession.tsx:69`): `session.blank && conversationPhase(...) === 'blank'`.

---

## 7. STOP / CANCEL

### 7.1 The button is **conditional**, not always available

`ui-conversation/src/client/skeleton/InputBar.tsx:274-302` **[VERIFIED]** — the primary button
*becomes* Stop only under exact conditions:

```ts
// An ordinary running session keeps Stop while the composer is empty or
// owner-blocked; an actionable draft gets the busy Send action, delivered
// through the same mode plain Enter resolves to. ...
const primaryStops = running && subagent === null && (empty || blocked !== undefined)
// Disabled native buttons may omit mouseleave; their tooltip must close from state.
const primaryDisabled = primaryStops ? stop === undefined : empty || disabled || machineBusy || uploadsPending
const interruptible = running && continuable
const primarySubmitMode = resolveSubmitMode(busyEnter, running, 'enter', steeringAvailable)
const plainMessageDraft = !empty && input?.phase === 'plain' && !draft.trimStart().startsWith('/')
const primaryLabel = primaryStops
  ? t('input.stop')
  : running && steeringAvailable && !disabled && !uploadsPending && plainMessageDraft
    ? t(primarySubmitMode === 'steer' ? 'input.send.steer' : 'input.send.queue')
    : t('input.send')
const onPrimary = (): void => {
  if (primaryStops) { stop?.(); return }
  if (keyboard === undefined) return
  if (!empty && !disabled && !machineBusy && !uploadsPending) keyboard.submit(primarySubmitMode)
}
```

Rules **[VERIFIED]**:
- **Ordinary session:** Stop is primary **only when the composer is EMPTY** (or owner-blocked).
  With a non-empty draft the primary stays Send (with a `send.queue` / `send.steer` label).
- **Continuable subagent child:** Send stays primary and Stop is exposed **independently**
  (`interruptible = running && continuable`) via a separate icon button at `:437-444`:
  ```tsx
  <Tooltip label={t('input.stop')} side="top" delayMs={500} disabled={stop === undefined}>
    ... aria-label={t('input.stop')} disabled={stop === undefined} onClick={stop}
  ```
  Comment at `:117-118`: *"A continuable child without its live parent cannot accept human input,
  but its independent Stop below stays available while it runs."*

### 7.2 What is sent and how it is confirmed

`apply.ts:389-393` **[VERIFIED]**:
```ts
stop: () => {
  scopedConversation(sessions, sessionId).cancel().catch(() => {
    // Stop failure is published through Session promptError.
  })
},
```

`ui-conversation/src/client/service.ts:506-511` **[VERIFIED]**:
```ts
/** Cancel the scoped session's in-flight turn while preserving Queue (failures land in promptError and reject, as in send). */
async cancel(): Promise<void> {
  const session = this.scopedSession('cancel')
  const result = await session.cancel()
  if (!result.ok) throw new Error(`conversation.cancel failed: ${result.error.code}: ${result.error.message}`)
}
```

`session.ts:325-346` **[VERIFIED]**:
```ts
async cancel(): Promise<RemoteResult<{ accepted: true }>> {
  const address = this.address
  const result = address !== undefined
    ? await this.remote.subagents.interruptByParent(
        address.childSessionId, address.parentSessionId, 'continuable')
    : await this.remote.session.cancel({ sessionId: this.sessionId })
  if (!result.ok) {
    this.promptError = { op: 'stop', error: result.error }
    this.notifier.markDirty()
  }
  return result
}
```

> **CONFIRMATION MODEL — this is important.** The RPC returns only `{ accepted: true }`. The UI does
> **NOT** optimistically flip `running` to false; it does **not** clear streamed text; it does not
> hide the turn status. The client **waits for the authoritative `running:false` status push**
> (§6.1), plus the durable `assistant/message` with `interrupted: true` for the interrupted node
> (`assistant.ts:212`) and `turn/end` for the turn tail.
>
> So: **`running` is Host-authoritative and never optimistically cleared.** The only optimistic
> local mutation on cancel is *none*. On failure the strip shows a toast (§14).

---

# PART B — TOOL CARDS

## 8. Tool call rendering: a keyed per-tool renderer registry

### 8.1 The registry is a **slot**, keyed by tool name, with a fallback

`ui-tool/src/client/apply.ts:33-41` **[VERIFIED]**:
```ts
ctx.slots.inject('conversation.chat.node', () => ctx.slots.register({
  name: 'conversation.chat.node',
  key: 'tool-call',
  locale: NS,
  children: {
    'tool.call.toolview': { kind: 'keyed', scope: 'session' },
  },
  inject: toolInject,
}, ToolCallTree))
```

Dispatch with fallback — `ToolCallTree.tsx:38-52` **[VERIFIED]**:
```tsx
return (
  <div className={css.callRow} data-chat-anchor-key={`call:${callId}`} data-chat-call-id={callId}>
    {autoReviewDenied
      ? <GenericToolCard {...owner} t={t} />
      : renderSlot('tool.call.toolview', owner, {
        entryKey: toolName,
        fallback: <GenericToolCard {...owner} t={t} />,
      })}
    {children}
  </div>
)
```

Built-in keyed entries (`apply.ts:43-50`): `bash`, `read`, `read_image`, `edit`+`write`
(`file-mutation-row.tsx:43-44`), `search`, `web`, `todo`, `ask-question`.
`cordis_define` is registered by ui-cordis (`tool-call-model.ts:38-46`) **[VERIFIED]**:
> *"`cordis_define` is deliberately absent: ui-cordis registers a keyed `tool.call.toolview`
> entry for it, and a keyed hit REPLACES the generic row (this table is only reached through
> GenericToolCard, the dispatch fallback in ToolCallTree)."*

### 8.2 Recursive subcalls (PTC dispatch) are a first-class tree

`ToolCallTree.tsx:55-93` **[VERIFIED]** — `ToolCallBranch` recurses over `block.subCalls`
rendered into `<div className={css.subCalls} data-subcalls>`. Depth is hard-capped at **256**
(`contract/chat-nodes.ts` / `model/tool-call-tree.ts:14`):
```ts
/** Fixed wire-safety ceiling for every recursive Tool call consumer. */
export const MAX_TOOL_CALL_TREE_DEPTH = 256
```
Cycles are rejected (`tool-call-tree.ts:185-198` `wouldCreateCycle`).

### 8.3 Diffs (file edits) — a per-tool card model, inline in the row

`ui-tool/src/client/tool/models/diff-card-model.ts` **[VERIFIED]**.

Constant (`:6-7`):
```ts
/** Room for a path, one removed/added pair, and three context lines on each side. */
export const CHAT_DIFF_MAX_LINES = 9
```

Intent is derived from the **call ARGUMENTS**, not from a server `view` field (`:44-81`):
```ts
type IntendedDiff = { tool: 'write' | 'edit' | 'str_replace_editor'; diff: DiffHunk }

function intendedDiff(block: ToolCallBlock): IntendedDiff | null {
  const parsed = parsedToolCall(block)
  if (parsed === null) return null
  if (parsed.name === 'str_replace_editor') {
    const { command, path, file_text: fileText, old_str: oldText, new_str: newText } = parsed.args
    if (typeof path !== 'string' || path.trim() === '') return null
    if (command === 'create') { ... return { tool: 'str_replace_editor', diff: { path, oldText: null, newText: fileText ?? '' } } }
    if (command === 'str_replace') { ... }
    return null
  }
  const { file_path: path } = parsed.args
  if (typeof path !== 'string' || path.trim() === '') return null
  if (!validEscalationFields(parsed.args)) return null
  if (parsed.name === 'write') {
    const { content } = parsed.args
    return typeof content === 'string' ? { tool: 'write', diff: { path, oldText: null, newText: content } } : null
  }
  if (parsed.name !== 'edit') return null
  const { old_string: oldText, new_string: newText, replace_all: replaceAll } = parsed.args
  if (typeof oldText !== 'string' || typeof newText !== 'string') return null
  if (replaceAll !== undefined && typeof replaceAll !== 'boolean') return null
  return { tool: 'edit', diff: { path, oldText: oldText || null, newText } }
}
```

**The APPLIED diff comes from the result's opaque `meta.diffs`**, validated strictly (`:83-112`):
```ts
function appliedDiffs(meta: unknown): DiffHunk[] | 'empty' | null {
  if (typeof meta !== 'object' || meta === null || Array.isArray(meta)) return null
  const diffs = (meta as Record<string, unknown>).diffs
  if (!Array.isArray(diffs)) return null
  if (diffs.length === 0) return 'empty'
  return narrowDiffs(diffs)
}

export function diffCardModel(block: ToolCallBlock): DiffCardModel | null {
  if (block.parentCallId !== undefined) return null          // root calls only
  const intended = intendedDiff(block)
  if (intended === null) return null
  if (!('kind' in block)) return { card: { diffs: [intended.diff] } }   // running → intended diff
  if (intended.tool === 'str_replace_editor') return null    // settles through Generic
  if (block.isError) return null
  const applied = appliedDiffs(block.meta)
  if (applied === null || applied === 'empty') {
    return intended.tool === 'write' ? { card: { diffs: [intended.diff] } } : null
  }
  return { card: { diffs: applied } }
}
```

`narrowDiffs` (`:28-40`) rejects the whole payload on any malformed member:
```ts
for (const hunk of diffs) {
  if (typeof hunk !== 'object' || hunk === null) return null
  const { path, oldText, newText } = hunk as Record<string, unknown>
  if (typeof path !== 'string') return null
  if (oldText !== null && typeof oldText !== 'string') return null
  if (typeof newText !== 'string') return null
  out.push({ path, oldText, newText })
}
```

> **Exact diff fields:** `meta.diffs[] = { path: string, oldText: string | null, newText: string }`.
> `oldText: null` means a whole-file creation. Rendered through the shared `DiffBlock` primitive.

**Collapsed-line diff stat** — `ToolRow.tsx:170-175` **[VERIFIED]**:
```tsx
const diffStat = useMemo(() => {
  if (diffBody === null) return null
  const { added, removed } = diffTotals(diffBody.card.diffs)
  return `+${added} -${removed}`
}, [diffBody])
const suffix = failureLine === null ? summarySuffix ?? diffStat : null
```

---

## 9. Tool card: running vs completed vs error

### 9.1 Exact state derivation

`tool-call-model.ts:237-243` **[VERIFIED]**:
```ts
export function toolRowModel(toolName: string, block: ToolCallBlock, cwd?: string, home?: string): ToolRowModel {
  const variant = classifyTool(toolName)
  const done = 'kind' in block
  const argsRaw = (done ? block.call?.argsRaw : block.argsRaw) ?? ''
  const state: ToolRowState = !done ? 'running'
    : block.error?.code === 'interrupted' ? 'stopped'
      : block.isError ? 'error' : 'ok'
```

State union (`:21`) **[VERIFIED]**:
```ts
/** Row state semantic; colors self-supplied via StateDot (design gives none). */
export type ToolRowState = 'running' | 'ok' | 'error' | 'stopped'
```

Variant union (`:18`) **[VERIFIED]**:
```ts
export type ToolRowVariant = 'search' | 'read' | 'bash' | 'write' | 'edit' | 'code' | 'others'
```

### 9.2 Per-state differences in the UI

| Aspect | running | ok | error | stopped |
|---|---|---|---|---|
| `data-state` attr | `running` | `ok` | `error` | `stopped` |
| Collapsed summary | derived from args | args-derived | **replaced by first line of output** | args-derived |
| Diff card | **intended** diff from args | **applied** diff from `meta.diffs` | **none** (`return null`) | none |
| Expandable | only if body/output/card | yes | yes | yes |
| Openfile link | yes | yes | **disabled** (`failureLine !== null`) | — |

Evidence — `ToolRow.tsx:163-179` **[VERIFIED]**:
```tsx
const status = stateStatus(state, t)
// A failure must replace, not supplement, the normal summary.
const failureLine = state === 'error' ? errorSummary ?? null : null
const summaryText = failureLine ?? terminalBody?.description ?? summary
...
const openFile = filePath !== undefined && onOpenFile !== undefined && failureLine === null
  ? (event) => { event.stopPropagation(); ... }
  : undefined
```

And `tool-call-model.ts:256-257` **[VERIFIED]**:
```ts
const output = done ? (resultText(block) || null) : null
const errorSummary = state === 'error' && output !== null ? firstLine(output) : null
```

A **screen-reader-only** status word is always emitted (`ToolRow.tsx:198`):
```tsx
{status !== null && <span className={css.visuallyHidden}>{status}</span>}
```

### 9.3 Auto-review denial takes a dedicated path

`ToolCallTree.tsx:34-37` **[VERIFIED]** — if `toolRowModel(...).autoReviewDenial !== null`, the
generic card is forced even for a keyed tool. Detection (`tool-call-model.ts:120-124`):
```ts
const error = block.error
if (error?.name !== 'AutoReviewDeniedError' || error.code !== 'AUTO_REVIEW_DENIED') return null
return { reason: typeof error.reason === 'string' ? error.reason : null }
```

---

## 10. Tool results / outputs: truncation, expansion, limits

### 10.1 Expansion is opt-in, per-row local state

`ToolRow.tsx:137, 154-162` **[VERIFIED]**:
```tsx
const [expanded, setExpanded] = useState(false)
...
const inputRaw = bodyRaw ?? null
const outputText = output ?? null
const card = askQuestionBody ?? terminalBody ?? diffBody ?? readBody ?? imageBody ?? searchBody ?? webBody
const expandable = inputRaw !== null || outputText !== null || card !== null
const open = expanded && expandable
const bodyText = useMemo(
  () => open && card === null && inputRaw !== null ? formatToolBody(variant, inputRaw) : null,
  [card, inputRaw, open, variant],
)
```

Body composition (`:238-251+`) **[VERIFIED]**:
```tsx
{askQuestionBody !== null
  ? <AskQuestionCard card={askQuestionBody} />
  : terminalBody !== null
    ? <TerminalBlock {...terminalBody.card} maxLines={Infinity} labels={terminalLabels} className={css.terminalBody} />
    : diffBody !== null
      ? <DiffBlock {...diffBody.card} labels={diffLabels} maxLines={CHAT_DIFF_MAX_LINES} className={css.diffBody} />
      : readBody !== null
        ? <ReadBlock {...readBody} labels={readLabels} maxLines={CHAT_READ_MAX_LINES} className={css.readBody} />
```

### 10.2 THE EXACT LINE LIMITS

| Card | Constant | Value | File:line |
|---|---|---|---|
| Diff | `CHAT_DIFF_MAX_LINES` | **9** | `diff-card-model.ts:7` |
| Read | `CHAT_READ_MAX_LINES` | **8** | `read-card-model.ts:17` |
| Search | `CHAT_SEARCH_MAX_LINES` | **8** | `search-card-model.ts:12` |
| Terminal | `maxLines` | **`Infinity`** | `ToolRow.tsx:245` |

`read-card-model.ts:14-17` **[VERIFIED]**:
```ts
 * same split [`CHAT_TERMINAL_MAX_LINES`](./terminal-card-model.ts) draws for
 ...
export const CHAT_READ_MAX_LINES = 8
```

### 10.3 Result flattening

`tool-call-model.ts:134-144` **[VERIFIED]**:
```ts
export function resultText(node: ToolResultNode): string {
  const parts: string[] = []
  for (const block of node.content) {
    if (block.type === 'text') parts.push(block.text)
    else parts.push(JSON.stringify(block, null, 2))
  }
  if (parts.length === 0 && node.error !== undefined) {
    parts.push(`${node.error.name}: ${node.error.code}`)
  }
  return parts.join('\n')
}
```

Argument body (`:216-227`) **[VERIFIED]** — the `code` variant shows the program, not the envelope:
```ts
export function formatToolBody(variant: ToolRowVariant, argsRaw: string): string | null {
  if (argsRaw === '') return null
  const parsed = parseArgs(argsRaw)
  if (parsed === undefined) return argsRaw
  if (variant === 'code' && typeof parsed === 'object' && parsed !== null) {
    const code = (parsed as Record<string, unknown>).code
    if (typeof code === 'string' && code !== '') return code
  }
  return JSON.stringify(parsed, null, 2)
}
```

Malformed/mid-stream args degrade gracefully (`:146-153`) **[VERIFIED]**:
```ts
function parseArgs(argsRaw: string): unknown {
  try { return JSON.parse(argsRaw) }
  catch {
    // Non-JSON args (mid-stream truncation): summary/body fall back to the raw string.
    return undefined
  }
}
```

Settled search results carry an explicit **truncation flag from the tool's own `meta`**
(`search-card-model.ts:88-91`) **[VERIFIED]**:
```ts
if (typeof meta.truncated !== 'boolean') return null
const common = { truncated: meta.truncated, total: meta.total }
const recovery = meta.truncated ? flattenContent(block.content) : undefined
```
Same for web (`web-card-model.ts:63,71,80`). Labeled via `primitive-labels.ts:67-72`
(`search.paths.truncated` / `search.matches.truncated`).

---

# PART C — INTERACTION COMPLETENESS

## 11. ALL distinct user-visible conversation states

### A. Layout phase (mutually exclusive, outermost)

| State | Trigger | User-visible representation |
|---|---|---|
| **`settling`** | `shellPhase==='blank' && openState==='loading' && summaryBlank!==true`, or continuable child with `parentAvailable===undefined` | Composer **hidden**; no hero, no flash. `ConversationMainPanel.tsx:123-129`, `data-phase="settling"` |
| **`hero`** | `sessionId===undefined` OR (`blank` AND (`open` OR `summaryBlank===true`)) | Centered `HeroShell` + `WorkspaceChip` + `conversation.hero.workspace` slot + hero composer with placeholder `t('placeholder.hero')`. `ConversationContent.tsx:240-247` |
| **`active`** | otherwise | Normal transcript + docked composer |

### B. Open lifecycle (orthogonal)

| State | Source | Representation |
|---|---|---|
| `cold` | `session.ts:91` | Not rendered as such; `DefaultConversationViews` returns `null` if blank. |
| `loading` | `session.ts:607` | Inline hint — `ChatView.tsx:771`: `{openState === 'loading' && <div className={css.hint}>{t('chat.loadingHistory')}</div>}` |
| `open` | `session.ts:623` | Normal. |
| `error` | `session.ts:628-629` | Inline error block — `ChatView.tsx:772-776`: `{t('chat.loadError', { message: openError.message, code: openError.code })}` |

### C. Interaction waits — **they take over the composer, they are not flow cards**

`ChatView.tsx:803-805` **[VERIFIED]** — this is explicit and must be ported literally:
```tsx
{/* No pending placeholders: questions (ui-user-questions) and approvals
    (ApprovalPanel) both take over the composer, so a flow card would
    double-render the same wait. */}
```

- **Awaiting approval** — `ui-approval/src/client/ApprovalPanel.tsx:12-54`: a card with
  `t('waiting')` strip, `pending.reason ?? t('escalation', { toolName })` headline, optional
  Tool-owned detail slot (`conversation.approval.detail`), and **two** buttons:
  `t('reject')` → `'rejected'`, `t('allowOnce')` → `'allowed-once'`. Local `answered` state
  disables both while in flight, and **re-enables on rejection** (`:26-29`):
  ```tsx
  const answer = (outcome: 'allowed-once' | 'rejected'): void => {
    setAnswered(true)
    void pending.answer(outcome).catch(() => { setAnswered(false) })
  }
  ```
  Selection is by `waterfall`, keyed `data-approval-key={pending.key}`.
- **Awaiting answer** — `ui-user-questions`: `QuestionComposer.tsx` / `PlanReviewPanel.tsx`,
  same composer-takeover mechanism, with a `draft-store.ts` for partial answers.

### D. Running / idle

- **running** — `running && <TurnStatus startTime={runningTurnStart} t={t} />` (`ChatView.tsx:808`).
  Text `t('chat.deepDiving')`, `role="status" aria-live="polite"`; a clock appears **only after
  15 s** (`ChatView.tsx:190`):
  ```ts
  const showClock = elapsedMs >= 15_000
  ```
  Anchored to the running turn's `turn/start` time (`runningTurnStart`, `:159-165`), falling back
  to mount time. Tick interval `1000` ms (`:185`).

### E. Blank / removed / subagent / archived

- **blank** — `session.blank` hides header chrome (`ConversationSession.tsx:69-74`) and the body
  (`DefaultConversationViews.tsx:34`).
- **removed** — `session.removed` → composer `disabled` (`InputBar.tsx:125`), placeholder
  `t('placeholder.unavailable')`.
- **subagent one-shot** — `ui-subagent/SubagentReadOnlyComposer.tsx:19-31`: replaces the composer
  with `role="status"` text `readonly.oneShot.title` / `readonly.oneShot.body`.
- **parent-offline continuable child** — placeholder `t('placeholder.parentOffline')`
  (`InputBar.tsx:323-324`); Stop stays live.
- **archived** — not a conversation-view state; surfaced by the sidebar
  (`ui-settings-unarchive-sessions`). **[INFERRED]**
- **disconnected** — no dedicated conversation-view state was found in these packages.
  **[INFERRED]** The transport throws a terminal `RemoteFailure` which flows into `openState='error'`
  (inline) or `promptError` (toast). Connection-wide chrome lives in `packages/client/connection`
  and `ui-layout` — **not verified here.**

### F. Per-turn / per-step states

- `TurnLocation.status` / `StepLocation.status` ∈ `'open' | 'closed' | 'unknown'`
  (`ui-conversation/src/client/contract/conversation.ts:86, 96`) **[VERIFIED]**.
- Assistant node `status` ∈ `'running' | 'settled' | 'interrupted'` (see §2.4).

---

## 12. Scroll behavior: auto-follow and the "jump to latest" affordance

### 12.1 THE THRESHOLD CONSTANTS

`ui-chat/src/client/chat/ChatView.tsx:19-20` **[VERIFIED]**:
```ts
const FOLLOW_THRESHOLD = 24
const SCROLL_SAMPLE_INTERVAL_MS = 500
```

The bottom test is used **five** times, always with the same `+1` slack
(`:356, :423, :485, :559`) **[VERIFIED]**:
```ts
el.scrollHeight - el.scrollTop - el.clientHeight <= FOLLOW_THRESHOLD + 1
```

### 12.2 Follow ownership is decided by a **ledger of programmatic writes**, not by raw geometry

`ChatView.tsx:27-30` **[VERIFIED]**:
```ts
/** Browser shrink clamps and recorded writes do not transfer scroll ownership. */
function readerMovedScroll(top: number, floor: number, observedTop: number): boolean {
  return Math.abs(top - Math.min(observedTop, floor)) > 0.5
}
```

`ChatView.tsx:544-579` **[VERIFIED]**:
```ts
onScrollRef.current = () => {
  const local = listRef.current
  if (local === null) return
  const el = scrollerOf(local)
  // Only reader input may make raw scroll geometry change follow ownership:
  // a delivered position that deviates from the observed-top ledger (every
  // programmatic write records itself there synchronously). This covers
  // wheel, touch, scrollbar, and keyboard alike without naming devices.
  // Browser shrink-clamps land exactly on the floor min and delayed
  // programmatic deliveries land on the ledger itself, so both preserve
  // the current ownership state.
  const floor = Math.max(0, el.scrollHeight - el.clientHeight)
  const movedByReader = readerMovedScroll(el.scrollTop, floor, observedTopRef.current)
  const isAtBottom = movedByReader
    ? floor - el.scrollTop <= FOLLOW_THRESHOLD + 1
    : atBottomRef.current
  if (!movedByReader && isAtBottom) {
    toBottom(el)
    return
  }
  atBottomRef.current = isAtBottom
  setAtBottom(isAtBottom)
  ...
}
```

### 12.3 Auto-scroll is driven by a **ResizeObserver**, gated on the pinned flag

`ChatView.tsx:632-650` **[VERIFIED]**:
```ts
// Streaming, tool disclosures, and other flow changes resize the column;
// the sticky composer resizes outside it. This observer owns ChatView's
// dynamic-height follow decisions and writes only while the reader is pinned.
useEffect(() => {
  const column = columnRef.current
  const local = listRef.current
  if (column === null || local === null || typeof ResizeObserver === 'undefined') return
  const scrollport = scrollerOf(local)
  const composer = scrollport.querySelector<HTMLElement>('[data-composer-seat]')
  // Flow-height changes (image loads, tool disclosures) move rows across the
  // reading line without a scroll event, so the active mark resyncs here too.
  const observer = new ResizeObserver(() => {
    followRef.current?.()
    activeTurnRef.current?.()
  })
  observer.observe(column)
  if (composer !== null) observer.observe(composer)
  return () => { observer.disconnect() }
}, [])
```

Note: there is **no** follow-on-content-change effect keyed on `followSig`. The ref
`followSigRef` is declared (`:334-337`) but the live mechanism is the ResizeObserver + the
scroll ledger. **[INFERRED]** the `followSig` was superseded by the observer.

`followRef` (`:621-631`) **[VERIFIED]**:
```ts
followRef.current = () => {
  if (scrollSamplePendingRef.current) return
  const local = listRef.current
  if (local !== null && atBottomRef.current) {
    const el = scrollerOf(local)
    el.scrollTop = el.scrollHeight
    observedTopRef.current = el.scrollTop
    chatScroll.save(null)
  }
}
```

### 12.4 The "jump to latest" affordance

`ChatView.tsx:826-834` **[VERIFIED]**:
```tsx
{!atBottom && (
  <div className={css.toBottomSlot}>
    <button
      type="button"
      className={css.toBottom}
      aria-label={t('chat.toBottom')}
      onClick={() => {
        const local = listRef.current
        ...
```

So: the button appears **purely on `!atBottom`**, i.e. as soon as the reader leaves the
`FOLLOW_THRESHOLD + 1 = 25px` bottom band. `toBottom()` (`:402-413`) clears the anchor, cancels a
pending jump, jumps, and saves `null` to `chatScroll`:
```ts
const toBottom = (el: HTMLElement): void => {
  anchorRef.current = null
  // Returning to the live tail supersedes a jump still landing.
  pendingJumpRef.current = null
  setBusyJumpTurn(current => current === null ? current : null)
  el.scrollTop = el.scrollHeight
  observedTopRef.current = el.scrollTop
  atBottomRef.current = true
  setAtBottom(true)
  chatScroll.save(null)
  setActiveTurn(turnNavigationItems.at(-1)?.turn ?? null)
}
```

### 12.5 Also present: a **Turn Navigator rail** with an active-turn mark

`ChatView.tsx:347-374` — a reading line at `min(96, clientHeight * 0.2)`:
```ts
const readingLine = el.getBoundingClientRect().top + Math.min(96, el.clientHeight * 0.2)
const reading = turnAtLine(local, readingLine)
```
With a jump-to-unloaded-turn loader (`navigateToTurn`, `:722-758`) using `loadThrough(seq)` and a
`pendingJumpRef` that is realized only once the target row actually renders (`:665-697`).

---

## 13. Message-level affordances

### 13.1 The shared action row

`ui-chat/src/client/chat/MessageIconActions.tsx:45-113` **[VERIFIED]** — exactly three built-ins
plus two slot seats:

```tsx
export interface MessageIconActionsProps {
  readonly text: string
  readonly time?: number | undefined
  readonly clock: 'start' | 'end'
  readonly onBranch?: (() => void) | undefined
  readonly branchUnavailable?: boolean | undefined
  readonly className?: string | undefined
  readonly extraActions?: ReactNode
  readonly usageAction?: ReactNode
  readonly t: ChatViewSlotProps['t']
}
```

- **Copy** — always. Swap-to-check for exactly **1000 ms** (`:71-74`), with an epoch guard so a
  stale promise cannot flip a newer click (`:57-76`):
  ```ts
  const onCopy = useCallback(() => {
    if (copied || copyPending.current) return
    const epoch = copyEpoch.current
    copyPending.current = true
    void writeClipboard(text).then((ok) => {
      if (epoch !== copyEpoch.current) return
      copyPending.current = false
      if (!ok) return
      setCopied(true)
      copyTimer.current = window.setTimeout(() => { copyTimer.current = null; setCopied(false) }, 1000)
    })
  }, [copied, text])
  ```
- **Branch (fork)** — only when `onBranch !== undefined`. When unavailable it stays **visible but
  aria-disabled** with a tooltip + hidden reason span (`:91-109`):
  ```tsx
  {/* Native disabled buttons do not deliver the hover/focus events Tooltip needs. */}
  <button ... aria-disabled={branchUnavailable || undefined}
    aria-describedby={branchUnavailable ? reasonId : undefined}
    data-unavailable={branchUnavailable || undefined}
    onClick={branchUnavailable ? undefined : onBranch}>
  ```
- **Timestamp** — `formatMessageClock(time, t, day)`, rendered **before** icons for user messages
  (`clock="start"`) and **after** for assistant (`clock="end"`).
- `extraActions` — the `conversation.chat.assistant-actions` **list** slot.
- `usageAction` — the turn usage/time pills.

### 13.2 Where each affordance is attached

| Surface | Where | File |
|---|---|---|
| User message | copy + branch + clock(start) | `MessageItem.tsx:327-335` |
| Pending steering bubble | copy + clock(start), **no branch, no time** | `MessageItem.tsx:248-255` |
| Local submission echo | copy + **submission.time** clock(start) | `MessageItem.tsx:301-309` |
| Assistant (turn tail) | copy + branch + clock(end) + usage + time | `TurnTailNodeView.tsx:44-66` |

**Assistant actions live on the TURN TAIL, not on the assistant row** — `TurnTailNodeView.tsx:12`
**[VERIFIED]**:
```tsx
/** Turn-local actions and feature tail over the Location index, independent of Assistant placement. */
```

Usage/time pills (`:52-64`) **[VERIFIED]**:
```tsx
usageAction={(
  <>
    {data.tokenUsage !== undefined && <TurnUsagePanel usage={data.tokenUsage} t={t} />}
    {runMs !== undefined && (
      <TurnTimePanel runMs={runMs} tokensPerSecond={data.tokensPerSecond}
        ttftMs={data.ttftMs} t={t} />
    )}
  </>
)}
```

Reveal policy (`:41`) **[VERIFIED]**:
```tsx
data-actions-reveal={isLatestTurn ? 'always' : 'hover'}
```

### 13.3 There is NO retry-message and NO edit-message affordance

**[VERIFIED] — absence.** Grepping the ui-chat surfaces shows:
- No "retry this message" button. The only `retry` in the chat tree is `ModelRetryItem`, which is a
  **Host-driven LLM retry countdown display** (`MessageItem.tsx:58-91`), not a user action.
- No "edit message" affordance. Editing exists only for the **draft** (composer) and, separately,
  the **Goal objective** (`GoalBar.tsx:73-78`).

**Feedback**: lives in a separate package `packages/client/ui-message-feedback` and mounts through
the `conversation.chat.assistant-actions` **list** slot (which `TurnTailNodeView.tsx:34-36` renders
as `assistantActions`). **[INFERRED from the slot wiring; I did not read that package.]**

### 13.4 Token usage / timing

`turn-tail.ts:149-162` **[VERIFIED]**:
```ts
const metrics = deriveTurnMetrics(finalized.map(candidate => candidate.finalNode)).get(end.event.data.turn)
const tokenUsage = context.start?.event.type === 'turn/start'
  ? deriveTurnTokenUsage(context.matches.map(match => match.event).filter(isSessionEvent))
  : undefined
return {
  turn: end.event.data.turn,
  seq: end.event.seq,
  time: end.event.time,
  closing,
  branchUnavailable: closing === null || latestTranscriptSeq !== closing.finalNode.seq,
  ...metrics?.ttftMs === undefined ? {} : { ttftMs: metrics.ttftMs },
  ...metrics?.tokensPerSecond === undefined ? {} : { tokensPerSecond: metrics.tokensPerSecond },
  ...tokenUsage === undefined ? {} : { tokenUsage },
}
```

So: **`ttftMs`, `tokensPerSecond`, `tokenUsage`**, plus `seq`/`time`/`closing`.
`branchUnavailable` is computed from whether the closing assistant is the last transcript event —
`turn-tail.ts:136-148` **[VERIFIED]**:
```ts
let latestTranscriptSeq = finalized.at(-1)?.finalNode.seq
for (const match of context.matches) {
  const event = match.event
  const candidate = event.type === 'tool/call'
    || (event.type === 'tool/result' && event.surfaceOp === 'append')
    || (event.type === 'turn/end' && event.data.reason.kind === 'error')
    || event.type === 'llm/retry'
    ? event.seq : undefined
  if (candidate !== undefined && (latestTranscriptSeq === undefined || candidate > latestTranscriptSeq)) {
    latestTranscriptSeq = candidate
  }
}
```

---

## 14. Host errors: how they are surfaced

There are **three** distinct error channels.

### 14.1 `turn/end` with `reason.kind === 'error'` → **inline flow node** (`turn-error`)

`ui-chat/src/client/conversation-nodes/turn-error.ts:31-49, 59-65` **[VERIFIED]**:
```ts
function failureFrom(match: ConversationMatch): TurnErrorState['failure'] | undefined {
  if (match.event.type !== 'turn/end' || match.event.data.reason.kind !== 'error') return undefined
  const failure = match.event.data.reason.error
  const display = displayFailure(failure)
  return { seq: match.event.seq, time: match.event.time,
    message: display.message, ...(display.code === undefined ? {} : { code: display.code }) }
}
...
  match: (event) => {
    if (event.type === 'turn/start') return { id: String(event.data.turn), role: 'start' }
    if (event.type === 'turn/end' && event.data.reason.kind === 'error') {
      return { id: String(event.data.turn), role: 'update' }
    }
    return null
  },
```

Rendered inline in the transcript. The AUTH special case — `event-projection.ts:151-162`
**[VERIFIED]**:
```ts
export function displayFailure(failure: unknown): DisplayFailure {
  if (failure === null || typeof failure !== 'object') return { message: String(failure) }
  const record = failure as { code?: unknown; message?: unknown }
  const code = typeof record.code === 'string' ? record.code : undefined
  // Provider AUTH messages may echo a masked or partially preserved credential.
  // Keep the raw diagnostic in the Session log, but never retain it in UI state.
  if (code === 'AUTH') return { code, message: '' }
  return { ...(code === undefined ? {} : { code }),
    message: typeof record.message === 'string' ? record.message : JSON.stringify(failure) }
}
```

And the renderer substitutes localized copy for AUTH (`MessageItem.tsx:50-56`) **[VERIFIED]**:
```ts
function failureMessage(message: string, code: unknown, t: ChatViewSlotProps['t']): string {
  return code === 'AUTH' ? t('message.failure.auth') : message
}
```

### 14.2 `api-session/error` → a **string** on the snapshot, with no turn position

Wired at `api/session-controller/src/client/index.ts:110-111` **[VERIFIED]**:
```ts
ctx.remote.$on('api-session/error', (sessionId, message) => {
  sessions.handleSessionError(sessionId, message)
})
```
→ `manager.ts:785-787` → `session.handleAgentError` (`session.ts:577-584`) **[VERIFIED]**:
```ts
/**
 * `api-session/error` relay: the outlet for live failures with no turn position.
 * @param message - the stringified error.
 */
handleAgentError(message: string): void {
  this.lastAgentError = message
  this.notifier.markDirty()
}
```

> **FINDING [VERIFIED]:** `lastAgentError` is written into `SessionSnapshot` but **no consumer in
> the packages I read renders it.** A repo-wide grep for `lastAgentError` outside tests returns only
> this writer plus test fixtures. It is a dead-end display channel in the current web client
> (the failure also renders as a `turn-error` node when the Host attaches it to a turn).

### 14.3 `promptError` (send/stop failures) → a **Toast**

`InputBar.tsx:96-110` **[VERIFIED]**:
```ts
// Prompt failures are ordinary failures (no create/attach transaction exists
// anymore): the toast announces promptError, the draft stays in the machine,
// and the user resubmits. A remount over a session whose machine still holds
// an unresolved promptError deliberately re-announces it once — the failure
// is still pending, and a transient banner is its only surface. Attachment
// rejections show product copy keyed by the wire reason — whichever domain
// refused them; other codes are developer-facing and keep the raw message
// plus code.
useEffect(() => {
  if (promptError === null) return
  const { error } = promptError
  showToast(error.code === 'session/attachment-invalid' || error.code === 'subagent/attachment-invalid'
    ? attachmentErrorText(t, error.details.reason, imageLimits)
    : `${error.message} (${error.code})`)
}, [promptError, showToast, t, imageLimits])
```

**Exact toast text format for non-attachment errors:** `` `${error.message} (${error.code})` ``.
The toast is `{ seq, text }` so an identical repeated message **restarts** the hold-then-fade cycle
rather than reusing the faded one (`:83-91`) **[VERIFIED]**.

### 14.4 History-open failure → inline block

`ChatView.tsx:772-776` **[VERIFIED]** — `t('chat.loadError', { message: openError.message, code: openError.code })`.

### 14.5 File-open refusal → a Modal

`ChatView.tsx:856-880` **[VERIFIED]** — `t('fileOpen.title')` + the wire message as the description,
with Cancel / Retry, Retry disabled while busy.

### 14.6 Terminal failure of a tool → `stopped`

`tool-call-model.ts:242` **[VERIFIED]**: `block.error?.code === 'interrupted' ? 'stopped'`.

### 14.7 Interrupted assistant → inline "stopped" marker

`AssistantMarkdown.tsx:138` **[VERIFIED]**:
```tsx
{interrupted && <span className={css.stopped}>{t('message.stopped')}</span>}
```

---

# PART D — PERIPHERAL STATE PACKAGES (skim)

All of these are **projection consumers** — they render Host-computed whole values, never fold
client-side. Read via the `useProjection(key)` seat.

| Package | Projection key / source | State surfaced | Where rendered |
|---|---|---|---|
| **ui-plan** | `useProjection('plan')` → `{active, pending}` | One chip. Effective target is `plan.pending ? !plan.active : plan.active` — **explicitly "a folded host value, not client optimism"** (`PlanModeControl.tsx:14-18`) | `conversation.input.plan` slot (`PlanChip`) |
| **ui-goal** | `useProjection('goal')` → `{goal: {id, revision, phase, objective, blockedReason}}`** + process-local `useGoalActivation` | Phases `active` \| `paused` \| `blocked` \| `complete`; activation `armed` \| `disarmed`. `complete` renders **nothing**. Labels: `phase.active.disarmed`, `phase.paused`, `phase.blocked`. Resume shown when paused OR (active AND disarmed) | `GoalBar.tsx:30-40, 86, 134-137`; docked above the composer |
| **ui-jobs** | `useSessions(s => s.jobsBySession[sessionId])` (from the control-frame `jobs` block, `manager.ts:672-677`) | Job statuses **`running` \| `stopping` \| `completed` \| `killed` \| `failed`** (closed union, `assertNever` fence); ordering: live by `startedAt` asc, then settled by `finishedAt` desc; duration ticks 1 s **only while the popover is open and a job is live** | `JobListAction.tsx:31-53, 77-85, 107-112`; `conversation.session.header.actions` slot. Renders `null` at zero jobs |
| **ui-subagent** | `session.subagent.address` + `parentAvailable` | Read-only composer takeover: reason `'one-shot'` \| `'parent-unavailable'`; breadcrumb lineage via `conversation.session.header.lineage` | `SubagentReadOnlyComposer.tsx:19-31`; `SubagentHeaderLineage.tsx` |
| **ui-workflow-run** | Conversation node `workflow-run` (a `conversation.chat.node` key) | Status union `running` \| `completed` \| `failed` \| `cancelled` \| `interrupted`; phases with `null`→`t('phase.unassigned')` and `''`→`t('phase.empty')`; disclosure mode `clean` \| `running` \| `abnormal` | `WorkflowRunPanel.tsx:30-53, 71-71`; inline flow node |
| **ui-deliverables** | `turn.data.get('deliverables')` → `{produced: {seq, path}[], presented?: PresentedPath[]}` | Turn-scoped produced files from **successful** `write`/`edit`/`str_replace_editor` calls (args-derived, not prose); dedup first-seen; `presented` from `deliverables/presented` events | `turn-deliverables.ts:157-215`; mounts into `conversation.chat.turnTail` **only when non-empty** (`selectProducedFiles` returns `null` otherwise, `:151-154`) |
| **ui-renderer** | — | Framework: registry + slot binding machinery (`registry.ts`, `bindings.tsx`, `scoped-slots.tsx`) | n/a |
| **ui-session** | — | `renderSessionArea`: renders the selected session subtree keyed by session id, or the `empty` branch (`session-provider.tsx:13-20`) | n/a |
| **store** | — | Framework-neutral `ObservableSnapshot` / `StoreSpec` / `defineStore` contract (`contract.ts`) | n/a |

---

# PART E — PORTING CHECKLIST (highest-risk items)

1. **Triple-rAF streaming publish.** Not a ms throttle. `assembly.ts:132-144`. Pick your Flutter
   equivalent (3 frames, or a ~50 ms coalescing window) — a naive `setState` per delta will not
   match.
2. **Fractional transient `seq`.** `durableCursor + 1 - 1/(transientInGap+1)`. Needed so transient
   rows sort after all durable events and before the next, without colliding with integers.
   `assistant-stream.ts:148` and `:81`.
3. **Withhold-then-release for settlements.** `acceptDurable` stages into `pending`; only the
   `end` frame's `outcome.seq` + `outcome.eventType` match releases it. Without this you will
   double-render the final message. `assistant-stream.ts:102-113, 160-181`.
4. **Render-time `rpcId` dedupe.** The snapshot retirement is one frame *late* on purpose.
   `ChatView.tsx:139-157`.
5. **`FOLLOW_THRESHOLD = 24` with `+1` slack (`<= 25`), plus the programmatic-write ledger**
   (`readerMovedScroll`, `observedTopRef`, 0.5 px tolerance). Scroll ownership must survive
   streamed reflow. `ChatView.tsx:19, 27-30, 544-579`.
6. **Layout phase `settling`** — do not render hero-then-dock; hide the composer until the open
   state resolves. `ConversationMainPanel.tsx:123-129`.
7. **Stop is not optimistic.** Only `{accepted, ok}`; the running bit flips on the status push.
8. **`displayFailure` AUTH scrubbing** — never retain the raw AUTH message in UI state.
   `event-projection.ts:157`.
9. **Diff `maxLines = 9`, read `= 8`, search `= 8`, terminal `= Infinity`.** Exact.
10. **Tool `state` is derived, not carried:** `running` (no `kind`) → `stopped` (`error.code === 'interrupted'`) → `error` (`isError`) → `ok`, in that precedence order.
11. **Approval/user-question waits take over the composer**; they are never flow cards.

---

# PART F — OPEN / UNVERIFIED

- Connection-level retry backoff constants: not read (`packages/client/connection`).
- `ui-message-feedback` package contents: not read (wired via the `assistant-actions` list slot).
- Whether `lastAgentError` has a consumer outside `packages/client` — grep found none, but I did not
  scan `packages/extensions/**` exhaustively.
- `ui-cordis`'s `tool.call.toolview` entry for `cordis_define`: referenced in a comment
  (`tool-call-model.ts:38-46`), not read.
