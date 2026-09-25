# DSH Web Client — Approval & User-Question Interaction Semantics (Porting Spec)

Source: `D:\software\deepseek-harness` (read-only inspection). All line references are `file:line` in that checkout.
Legend: **[VERIFIED]** = read directly from source/test. **[INFERRED]** = derived by composing verified facts.

---

## 0. Architecture in one paragraph (read this first) [VERIFIED]

Neither flow is a "dialog". Both are **composer takeovers**: the normal chat input bar at the bottom
of the conversation is *replaced* by a card, in-place, for the session that owns the request.
The mechanism is a **slot chain** named `conversation.composer`:

- `packages/client/ui-conversation/src/client/apply.ts:248` — `'conversation.composer': { kind: 'chain', scope: 'session' }`
- `packages/client/ui-conversation/src/client/skeleton/ConversationContent.tsx:249-252` — renders the chain with `{ fallback: composerBar, fallbackOnly: sessionId === undefined, overlay: true }`

Chain election (`packages/client/ui-slots/src/index.ts:259-270`): selectors run in ascending `priority`;
first non-null wins and becomes the component's `matched` prop; all-null falls back to the normal composer bar.
`overlay: true` means the fallback composer bar **stays mounted but hidden** (index.ts:250-256) — so a
user's typed draft survives a takeover and reappears after the request resolves.

Each pending request is published into a **per-session single-slot map**, and the chain's owner prop
`pendingInteraction` is read from it:
`packages/client/ui-conversation/src/client/contract/slots.ts:350-357`
```ts
export interface ComposerChainProps {
  sessionId: SessionId | undefined
  session: SessionSnapshot | undefined
  /** Effective business-owned interaction awaiting the user in this Session. */
  pendingInteraction: SessionPendingInteraction | undefined
}
```
`ConversationContent.tsx:114-115` is the read:
```ts
const pendingInteraction = useSessionPendingInteraction(snapshot =>
  sessionId === undefined ? undefined : snapshot.get(sessionId))
```

**Consequence for a Flutter port:** being on session X shows *only* X's pending interaction. There is
no global modal layer. Requests for other sessions are surfaced as **sidebar row status dots**, not as
cards (see §11).

---

## 1. APPROVALS

### 1.1 The exact user choices: strictly BINARY [VERIFIED]

Two buttons. Not three, not four. There is **no** "allow always", **no** "allow for this session",
**no** "always reject".

`packages/client/ui-approval/src/client/ApprovalPanel.tsx:44-51`
```tsx
<div className={css.actionRow}>
  <Button variant="outline" className={css.reject} disabled={answered} onClick={() => { answer('rejected') }}>
    {t('reject')}
  </Button>
  <Button variant="primary" disabled={answered} onClick={() => { answer('allowed-once') }}>
    {t('allowOnce')}
  </Button>
</div>
```

The handler is typed to exactly two literals — the type system forbids a third:
`ApprovalPanel.tsx:25-29`
```tsx
const [answered, setAnswered] = useState(false)
const answer = (outcome: 'allowed-once' | 'rejected'): void => {
  setAnswered(true)
  void pending.answer(outcome).catch(() => { setAnswered(false) })
}
```

The exported decision type is the same closed pair:
`packages/client/ui-approval/src/client/contract/slots.ts:63-64`
```ts
/** Decisions this interactive Client presentation can return. */
export type ApprovalDecision = 'allowed-once' | 'rejected'
```

**Option labels/ids.** The UI button text comes from the `approval` locale namespace
(`packages/client/ui-approval/src/client/locales.ts:4-10` zh = key-set source of truth):
```ts
export const zh = {
  waiting: '等待审批',
  'detail.aria': '审批详情',
  escalation: '工具 {toolName} 请求越权执行',
  reject: '拒绝',
  allowOnce: '允许一次',
} satisfies Record<string, string>
```
`locales.ts:16-22` (en):
```ts
export const en = {
  waiting: 'Waiting for approval',
  'detail.aria': 'Approval details',
  escalation: 'Tool {toolName} requests privileged execution',
  reject: 'Reject',
  allowOnce: 'Allow once',
} satisfies Record<ApprovalKey, string>
```

| Button | Locale key | zh label | en label | Internal value | Button variant | Order |
|---|---|---|---|---|---|---|
| Reject | `reject` | `拒绝` | `Reject` | `'rejected'` | `outline` (+ danger hover) | **left** |
| Allow once | `allowOnce` | `允许一次` | `Allow once` | `'allowed-once'` | `primary` | **right** |

Test confirmation — `packages/client/ui-approval/tests/ui-approval.client.spec.tsx:326-339`:
```tsx
it('renders fallback copy without detail and returns rejection', async () => {
  const pending = new PendingApproval(id('s1'), { toolName: 'bash' })
  const props = panelProps(pending)
  render(<ApprovalPanel {...props} />)

  expect(screen.getByText('Tool bash asks')).toBeTruthy()
  expect(screen.getByRole('group', { name: 'Approval details' })).toBeTruthy()
  expect(props.renderSlot).not.toHaveBeenCalled()
  fireEvent.click(screen.getByRole('button', { name: 'Reject' }))

  await expect(pending.result).resolves.toBe('rejected')
  expect(screen.getByRole<HTMLButtonElement>('button', { name: 'Reject' }).disabled).toBe(true)
  expect(screen.getByRole<HTMLButtonElement>('button', { name: 'Allow once' }).disabled).toBe(true)
})
```

✅ **Answer to Q1: binary. `拒绝/Reject` → `'rejected'`; `允许一次/Allow once` → `'allowed-once'`.**

> ⚠️ **Trap — there ARE two more outcome strings, but they are NOT user choices.**
> `packages/interaction/user-approval/src/types.ts:28-32`
> ```ts
> /**
>  * Closed approval outcomes: a one-shot grant, explicit rejection, withdrawn
>  * request, or unavailable answerer. Callers fail closed on `unavailable`.
>  */
> export type ApprovalOutcome = 'allowed-once' | 'rejected' | 'cancelled' | 'unavailable'
> ```
> `'cancelled'` and `'unavailable'` are produced by the **Host**, never by a button. A port must
> model all four as incoming/outgoing states but only render two buttons. `types.ts:47-48`:
> ```ts
> /** Every {@link ApprovalOutcome}, for runtime normalization of answerer returns. */
> const OUTCOMES: readonly ApprovalOutcome[] = ['allowed-once', 'rejected', 'cancelled', 'unavailable']
> ```

The package's own README states the limitation explicitly —
`packages/client/ui-approval/README.md:34`:
> - **The panel exposes transient decisions only** — it supports allow-once and reject; persistent permission policy remains owned by Host-side approval packages.

And `packages/interaction/user-approval/README.md:155`:
> - **Only one-shot grants exist** — the outcome vocabulary has `allowed-once` but no `allow-always`, remembered rule, revocation, or grant store; session policy is only `ask` / `never`.

### 1.2 Exact `outcome` value sent to the Host for each choice [VERIFIED]

**There is no `{kind:'result', value:...}` anywhere in the client approval code.** The client returns the
**bare string** from its waterfall listener; the Remote-Event bridge wraps it.

Layer 1 — the button resolves the carrier's promise with the bare literal
(`ApprovalPanel.tsx:26-28`, `slots.ts:118-126`):
```ts
/**
 * Resolve the Host waterfall with the user's decision.
 * @param outcome - supported interactive decision.
 */
answer(outcome: ApprovalDecision): Promise<void> {
  return settlePendingComposer(() => {
    this.finish(() => { this.#resolve(outcome) })
  }, 'pending approval settlement failed')
}
```

Layer 2 — the Remote Event listener simply **returns** that value to the waterfall
(`packages/client/ui-approval/src/client/index.ts:35-68`, esp. 57-63):
```ts
async function answerApproval(
  ctx: ClientContext,
  owner: ClientContext,
  request: ClientApprovalRequest,
  next: ClientApprovalNext,
  registerPendingInteraction: PendingInteractionPublisher<PendingApproval>,
): Promise<ClientApprovalOutcome> {
  const sessionId = ctx.sessions.scopeOf(owner)
  if (sessionId === undefined) return next()
  const pending = new PendingApproval(sessionId, { /* toolName, callId?, reason?, signal? */ })
  const completed = Promise.withResolvers<void>()
  const remove = registerPendingInteraction(pending, async () => {
    pending.delegate()
    await completed.promise
  })
  try {
    try {
      return await pending.result          // ← the bare 'allowed-once' | 'rejected'
    } catch (error) {
      if (pending.isDelegation(error)) return await next()
      throw error
    }
  } finally {
    remove()
    completed.resolve()
  }
}
```

Layer 3 — the bridge converts a returned value into `{kind:'result', value}`
(`packages/api/gateway/src/client/remote-events.ts:242-247`):
```ts
if (value !== REMOTE_EVENT_NEXT && value !== undefined && !isRemoteJsonValue(value)) {
  throw new TypeError('Remote event listener result is not lossless JSON data')
}
return value === REMOTE_EVENT_NEXT
  ? { kind: 'next' }
  : { kind: 'result', value }
```
and `remote-events.ts:207-213` collapses `value === undefined` to a valueless `{kind:'result'}`:
```ts
const result: RemoteEventResult = {
  clientId,
  eventId: frame.eventId,
  outcome: outcome.kind === 'result' && outcome.value === undefined
    ? { kind: 'result' }
    : outcome,
}
```

**Exact wire payloads** (`packages/api/gateway/src/stream-protocol.ts:86-94` is the wire type):
```ts
export interface RemoteEventResult {
  readonly clientId: RemoteEventClientId
  readonly eventId: RemoteEventId
  readonly outcome:
    | { readonly kind: 'next' }
    | { readonly kind: 'result'; readonly value?: unknown }
    | { readonly kind: 'rejected'; readonly error: RemoteEventRejection }
}
```

| UI choice | DOM label | Carrier resolution | **Exact HTTP body to `$events/result`** |
|---|---|---|---|
| Allow once | `允许一次` / `Allow once` | `'allowed-once'` | `{"clientId":"<uuid>","eventId":"<uuid>","outcome":{"kind":"result","value":"allowed-once"}}` |
| Reject | `拒绝` / `Reject` | `'rejected'` | `{"clientId":"<uuid>","eventId":"<uuid>","outcome":{"kind":"result","value":"rejected"}}` |
| *(not a button)* Host withdrew / aborted | — | `abort(reason)` → rejects | `{"...","outcome":{"kind":"rejected","error":{"name":"Error","message":"..."}}}` |
| *(not a button)* Domain unloaded → delegate | — | `delegate()` → rejects with private symbol | `{"clientId":"...","eventId":"...","outcome":{"kind":"next"}}` |
| *(not a button)* No session scope | — | `return next()` immediately | `{"clientId":"...","eventId":"...","outcome":{"kind":"next"}}` |

✅ **Direct answer: "allow once" is the string `'allowed-once'` (hyphenated), delivered as
`outcome.value`. "reject" is `'rejected'`. It is NOT `'allowed'`, NOT `'allow_once'`, NOT `'allow-once'`.**

> Reference cross-check: the ACP adapter *does* use `'allow-once'` for a different, unrelated option id, and
> maps it to the canonical value — `packages/acp/acp/src/index.ts:171`:
> ```ts
> return outcome.optionId === 'allow-once' ? 'allowed-once' : 'rejected'
> ```
> Do not confuse the ACP `optionId` with the DSH outcome vocabulary.

**Delegation (`{kind:'next'}`) is not a user choice** — it means "this client declines to answer, ask the
next answerer." The Host then continues its waterfall. `packages/client/ui-approval/src/client/index.ts:60-62`
+ `contract/slots.ts:128-141`:
```ts
/** Delegate an unanswered request to the next waterfall listener. */
delegate(): void {
  if (this.#settled) return
  this.finish(() => { this.#reject(this.#delegated) })
}

isDelegation(reason: unknown): boolean {
  return reason === this.#delegated
}
```

⚠️ **`'cancelled'` is never sent by the web client.** The client's `abort()` path sends
`{kind:'rejected', error}`, not `'cancelled'`. `'cancelled'` originates Host-side when the request's own
`AbortSignal` fires (`packages/interaction/user-approval/src/index.ts:286-299`):
```ts
if (signal === undefined) return answer
return await new Promise<ApprovalOutcome>((resolve) => {
  const onAbort = () => {
    signal.removeEventListener('abort', onAbort)
    resolve('cancelled')
  }
  signal.addEventListener('abort', onAbort, { once: true })
  void answer.then((outcome) => {
    signal.removeEventListener('abort', onAbort)
    // After an abort won the race this resolve is a settled-promise no-op:
    // the late answer is discarded by construction.
    resolve(outcome)
  })
})
```

**How the Host consumes each outcome** — `packages/core/tools/src/index.ts:1722-1737`:
```ts
switch (outcome) {
  case 'allowed-once': return { decision: { kind: 'allow' }, approvalCancelled: false }
  case 'rejected': return {
    decision: { kind: 'deny', reason: `the user rejected tool "${exec.name}"` },
    approvalCancelled: false,
  }
  case 'cancelled': return {
    decision: { kind: 'deny', reason: `approval for tool "${exec.name}" was cancelled` },
    approvalCancelled: true,
  }
  case 'unavailable': return {
    decision: { kind: 'deny', reason: `tool "${exec.name}" requires approval, but no approval channel is available` },
    approvalCancelled: false,
  }
  default: return assertNever(outcome, 'ApprovalOutcome')
}
```
Sandbox escalation is an analogous consumer — `packages/sandbox/sandbox/src/escalation.ts:180-188`:
```ts
switch (outcome) {
  case 'allowed-once': return mode as SandboxMode
  case 'rejected': throw new Error(`the user rejected escalating this ${subject} to "${mode}"`)
  case 'cancelled': throw new Error(`approval for escalating to "${mode}" was cancelled`)
  case 'unavailable': throw new Error(`sandbox escalation to "${mode}" requires approval, but no approval channel is available`)
  default: return assertNever(outcome, 'EscalationOutcome')
}
```

### 1.3 How the approval is rendered [VERIFIED]

**It is an inline card that takes over the composer seat at the bottom of the conversation.**
NOT a modal dialog, NOT a banner, NOT an inline card in the transcript.

Container: `packages/client/ui-approval/src/client/ApprovalPanel.module.css:1-18`
```css
.root {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 8px calc(var(--dsh-composer-side-clearance) + 16px) 12px;
}

.card {
  overflow: hidden;
  width: 100%;
  max-width: var(--dsh-chat-content-width);
  border: 1px solid var(--dsw-alias-state-warn-secondary);
  border-radius: 20px;
  background: var(--dsw-specific-input-major);
  box-shadow: var(--dsw-shadow-lv2);
  ...
}
```
Note `max-width: var(--dsh-chat-content-width)` — the card is as wide as a chat message, not the viewport.
`border-radius: 20px`, warning-colored border, level-2 shadow.

Structure (`ApprovalPanel.tsx:30-54`), four bands:

```tsx
<div className={css.root} data-approval-key={pending.key}>
  <div className={css.card}>
    <div className={css.strip}><span className={css.dot} />{t('waiting')}</div>
    <div
      className={css.body}
      data-approval-scroll=""
      tabIndex={0}
      role="group"
      aria-label={t('detail.aria')}
    >
      <div className={css.headline}>{pending.reason ?? t('escalation', { toolName: pending.toolName })}</div>
      {detail !== null && <div className={css.command}>{detail}</div>}
    </div>
    <div className={css.actionRow}>…two buttons…</div>
  </div>
</div>
```

| Band | Content | Evidence |
|---|---|---|
| **strip** (top, warning-tinted) | 8px warning dot + `等待审批` / `Waiting for approval` | `ApprovalPanel.tsx:33`, `module.css:20-37` |
| **headline** | `reason` verbatim if present, else `工具 {toolName} 请求越权执行` / `Tool {toolName} requests privileged execution` | `ApprovalPanel.tsx:41` |
| **detail** (optional, monospace) | whatever the tool plugin registered for `conversation.approval.detail` | `ApprovalPanel.tsx:42`, `module.css:56-62` (`font-family: var(--ds-font-family-code); word-break: break-all`) |
| **actionRow** (bottom, right-aligned) | Reject (outline) then Allow once (primary) | `ApprovalPanel.tsx:44-51`, `module.css:64-69` |

Body is a **scrollport** capped at the composer text height — `module.css:39-47`:
```css
.body {
  ...
  max-height: var(--dsh-composer-text-max-height);
  overflow-y: auto;
  padding: 12px 16px 0;
}
```
Accessibility: `role="group"` + `aria-label="审批详情"/"Approval details"`, `tabIndex={0}` so the
scroll region is keyboard-reachable. The root carries `data-approval-key={pending.key}` for test targeting.

**What it shows — precise list:**
- ✅ Tool **name** — but **only as fallback text inside the headline** (`escalation` template). When the
  Host supplies a `reason`, the tool name is **not displayed at all**. `ApprovalPanel.tsx:41`.
- ✅ **Reason** — the headline, verbatim, when present.
- ❌ **Tool arguments** — never. The card does not receive them.
- ❌ **Diff** — never.
- ✅ **Optional tool-owned detail** — via a correlated `callId`.

**The `detail` mechanism.** `ApprovalPanel.tsx:12-18`:
```tsx
export function ApprovalPanel(props: ApprovalComposerProps) {
  const approval = props.matched
  const detail = approval.callId === undefined
    ? null
    : props.renderSlot('conversation.approval.detail', { callId: approval.callId })
  return <ApprovalFlow key={approval.key} pending={approval} detail={detail} t={props.t} />
}
```
The slot contract (`contract/slots.ts:35-49`):
```ts
interface SlotMap {
  /** Optional detail for the Tool call correlated with an approval request. */
  'conversation.approval.detail': {
    kind: 'single'
    scope: 'session'
    owner: ApprovalDetailOwnerProps
  }
}

/** Stable identity handed to an optional approval-detail renderer. */
export interface ApprovalDetailOwnerProps {
  /** Tool call correlated with the request. */
  callId: ToolCallId
}
```
The only in-repo registration is chat's shell-command extractor —
`packages/client/ui-chat/src/client/chat/ApprovalCommand.tsx:16-40`:
```tsx
export function commandOf(call: ApprovalToolCall | undefined): string | undefined {
  if (call === undefined) return undefined
  try {
    const args = JSON.parse(call.argsRaw) as Record<string, unknown>
    return typeof args.command === 'string' ? args.command : undefined
  } catch {
    return undefined
  }
}

export function ApprovalCommand({ callId, useChat }: PropsRuntime<'conversation.approval.detail'>) {
  const command = useChat((snapshot) => {
    for (const node of snapshot.nodes.values()) {
      const root = node.kind === 'tool-call' ? (node as ChatNode<'tool-call'>).data.root : undefined
      if (root !== undefined && root.callId === callId && !('kind' in root)) return commandOf(root)
    }
    return undefined
  })
  return command ?? null
}
```
**So the detail band shows the shell `command` string, if and only if the correlated tool call's JSON args
have a string `command` field.** It is registered at `packages/client/ui-chat/src/client/apply.ts:176-177`.
Registered by `ui-chat`, not by the approval package. Otherwise the band is absent (`return command ?? null`).

`renderSlot` is only called when `callId !== undefined` — asserted by
`tests/ui-approval.client.spec.tsx:333` (`expect(props.renderSlot).not.toHaveBeenCalled()`) and
`:352-354`:
```tsx
expect(renderSlot).toHaveBeenCalledWith('conversation.approval.detail', {
  callId: 'call-1',
})
```
and the returned node renders inside `.command` (`:351`, `expect(screen.getByText('pnpm test')).toBeTruthy()`).

Test for the reason-only path — `tests/ui-approval.client.spec.tsx:341-358`:
```tsx
it('renders correlated detail and returns allow-once', async () => {
  const pending = new PendingApproval(id('s1'), {
    toolName: 'bash',
    callId: 'call-1' as ToolCallId,
    reason: 'Run this exact command',
  })
  const renderSlot = vi.fn(() => <code>pnpm test</code>)
  render(<ApprovalPanel {...panelProps(pending, renderSlot)} />)

  expect(screen.getByText('Run this exact command')).toBeTruthy()
  expect(screen.getByText('pnpm test')).toBeTruthy()
  ...
  fireEvent.click(screen.getByRole('button', { name: 'Allow once' }))
  await expect(pending.result).resolves.toBe('allowed-once')
})
```

**Client-visible request fields** — `contract/slots.ts:51-61`:
```ts
/** Client-visible fields of an approval request projected through Remote Events. */
export interface ApprovalPresentationRequest {
  /** Tool requesting the decision. */
  readonly toolName: string
  /** Tool call correlated with the request. */
  readonly callId?: ToolCallId
  /** Human-readable reason supplied by the requester. */
  readonly reason?: string
  /** Cancellation projected from the Host waterfall. */
  readonly signal?: AbortSignal
}
```

**Disabled/enable behavior:** clicking disables BOTH buttons immediately (`answered` state),
optimistically. If the send fails, both **re-enable** — `ApprovalPanel.tsx:26-29` and the test at
`tests/ui-approval.client.spec.tsx:360-372`:
```tsx
it('re-enables actions when answering fails', async () => {
  const pending = new PendingApproval(id('s1'), { toolName: 'bash' })
  vi.spyOn(pending, 'answer').mockRejectedValue(new Error('transport closed'))
  render(<ApprovalPanel {...panelProps(pending)} />)

  fireEvent.click(screen.getByRole('button', { name: 'Allow once' }))
  expect(screen.getByRole<HTMLButtonElement>('button', { name: 'Allow once' }).disabled).toBe(true)
  await waitFor(() => {
    expect(screen.getByRole<HTMLButtonElement>('button', { name: 'Allow once' }).disabled).toBe(false)
  })
  ...
})
```
⚠️ Note there is **no error text** shown on failure in the approval panel (unlike the question flow, which
does show one). The approval card silently re-arms. **[VERIFIED by absence — the component has no error state.]**

**Remount axis:** `<ApprovalFlow key={approval.key} …>` (`ApprovalPanel.tsx:17`) — a new request key forces a
fresh component so `answered` resets. Keys are globally incrementing — `contract/slots.ts:66,96-97`:
```ts
let nextApprovalKey = 0
…
nextApprovalKey += 1
this.key = `approval:${String(nextApprovalKey)}`
```

### 1.4 Timeout, cancel, resolved-elsewhere [VERIFIED]

**There is NO client-side timeout.** No `setTimeout`, no expiry, no countdown in `ui-approval`. The card
persists indefinitely until one of five things happens.

The carrier is a `Promise.withResolvers` (`contract/slots.ts:101-104`) settled by exactly one of:
`answer()`, `delegate()`, `abort()`. `finish()` enforces single settlement — `contract/slots.ts:152-159`:
```ts
private finish(settle: () => void): void {
  if (this.#settled) throw new Error(`pending approval ${this.key} is already settled`)
  this.#settled = true
  if (this.#signal !== undefined && this.#onAbort !== undefined) {
    this.#signal.removeEventListener('abort', this.#onAbort)
  }
  settle()
}
```

| Trigger | Mechanism | Client reaction | Wire result |
|---|---|---|---|
| User clicks a button | `answer(outcome)` | both buttons disabled | `{kind:'result', value:'allowed-once'\|'rejected'}` |
| Host aborts the request (turn cancelled, tool call ended) | `signal` fires → `abort(reason)` (`slots.ts:110-115`) | `#reject(reason)` propagates; the listener rethrows; the pending entry is removed in `finally` | `{kind:'rejected', error:{name,message}}` |
| Request's signal was **already** aborted at construction | `slots.ts:115` (`if (request.signal.aborted) onAbort()`) | immediate rejection | same |
| Plugin/session teardown (transport loss, scope release) | `registerPendingInteraction` delegate (`index.ts:53-56`) | `pending.delegate()` → resolves to private symbol → `return await next()` | `{kind:'next'}` — falls through to another answerer |
| No session scope resolvable | `index.ts:42-43` (`if (sessionId === undefined) return next()`) | never published; nothing rendered | `{kind:'next'}` |

**Client-side cancel/close button: NONE for approvals.** The card has no ✕, no Esc handler

**[VERIFIED by absence — `ApprovalPanel.tsx` renders exactly two buttons].** The user's only exit is
Reject. This is a deliberate asymmetry with the question flow, which *does* have a dismiss button.

**"How does the UI learn it was resolved elsewhere?" — it does, via three channels:**

1. **Host cancellation frame.** The Host pushes a `{type:'cancel', eventId}` frame when the request
   settles for any other client. `packages/api/gateway/src/index.ts:565-576`:
   ```ts
   private finishRemoteEvent(pending: PendingRemoteEvent): void {
     this.pendingRemoteEvents.delete(pending.id)
     pending.releaseSignal()
     pending.releaseContext()
     const clients = new Set(pending.deliveries)
     for (const client of clients) this.removeRemoteEventDelivery(pending, client)
     const cancellation: RemoteEventCancellationFrame = {
       type: 'cancel',
       eventId: pending.id,
     }
     for (const client of clients) client.queue.push(cancellation)
   }
   ```
   Client side — `packages/api/gateway/src/client/remote-events.ts:147-150`:
   ```ts
   if (frame.type === 'cancel') {
     active.get(frame.eventId)?.abort(new Error('client api: Remote event was cancelled by the Host'))
     continue
   }
   ```
   That abort fires the `AbortSignal` handed to the waterfall, which `PendingApproval` subscribed to,
   which rejects `pending.result`, which throws out of the listener, which triggers the `finally { remove() }`
   → the pending entry leaves the per-session map → **the chain elects nothing and the normal composer
   returns.** **[INFERRED — the composition of `remote-events.ts:148` + `slots.ts:110-115` + `index.ts:64-67`
   is verified at each step; no single test asserts the end-to-end visual.]**

2. **Scope/fiber disposal.** When the owning Agent Context is released, the Host cancels
   (`packages/api/gateway/src/index.ts:470-479`):
   ```ts
   const dispose = source.context.value.effect(
     () => () => {
       this.cancelRemoteEvent(
         pending,
         new Error('typert gateway: Remote event Agent Context was released'),
       )
     },
     `api-gateway: Remote event ${JSON.stringify(source.event)}`,
   )
   ```

3. **Domain unload → delegation**, not cancellation. `packages/client/ui-session/src/client/index.ts:304-323`:
   ```ts
   registerPendingInteraction<T extends SessionPendingInteractionBase>(
     precedence: (interaction: T) => number,
   ): PendingInteractionPublisher<T> {
     const domain = new PendingInteractionDomain(precedence, () => {
       this.publishPendingInteractions()
     })
     const runtimeDomain = domain as unknown as RuntimePendingDomain
     this.ctx.effect(() => {
       this.pendingDomains.push(runtimeDomain)
       this.publishPendingInteractions()
       return async () => {
         const delegates = domain.release()
         const index = this.pendingDomains.indexOf(runtimeDomain)
         this.pendingDomains.splice(index, 1)
         this.publishPendingInteractions()
         await Promise.allSettled(delegates.map(delegate => Promise.resolve().then(delegate)))
       }
     }, 'uiSession.registerPendingInteraction()')
     return (interaction, delegate) => domain.publish(interaction, delegate)
   }
   ```
   Note `release()` **clears the visible values first** (`index.ts:96-101`), then awaits the delegates —
   asserted at `packages/client/ui-session/tests/ui-session.client.spec.ts:500-523`.

Tests that pin the cancel behavior:
- `tests/ui-approval.client.spec.tsx:247-265`:
  ```tsx
  it('propagates request cancellation after removing the pending object', async () => {
    …
    controller.abort(reason)
    await expect(result).rejects.toBe(reason)
    expect(bench.pending.getSnapshot()).toEqual([])
  ```
- `tests/ui-approval.client.spec.tsx:267-281`:
  ```tsx
  it('delegates an active request when its interaction domain unloads', async () => {
    …
    await bench.releasePending()
    await expect(result).resolves.toBe('unavailable')   // ← the test's `next`
    expect(next).toHaveBeenCalledOnce()
  ```
- `tests/ui-approval.client.spec.tsx:141-152` (already-aborted signal rejects with the signal's own reason):
  ```tsx
  it('rejects with an already-aborted signal reason', async () => {
    const reason = new Error('host cancelled')
    controller.abort(reason)
    const pending = new PendingApproval(id('s1'), { toolName: 'read', signal: controller.signal })
    await expect(pending.result).rejects.toBe(reason)
  })
  ```
- `tests/ui-approval.client.spec.tsx:154-165` (no-reason fallback text):
  ```tsx
  await expect(pending.result).rejects.toThrow('approval request was aborted')
  ```
  from `slots.ts:110-112` — `this.abort(request.signal?.reason ?? new Error('approval request was aborted'))`.

### 1.5 Approvals from a DIFFERENT session/agent [VERIFIED]

**They are never rendered as a card in the current session.** Two distinct mechanisms exist.

**(a) Per-session exclusivity.** The pending map is keyed by `SessionId` and holds exactly **one**
interaction per session (`packages/client/ui-session/src/client/index.ts:366-386`):
```ts
private publishPendingInteractions(): void {
  const next = new Map<SessionId, {
    interaction: SessionPendingInteractionBase
    precedence: number
  }>()
  for (const domain of this.pendingDomains) {
    for (const interaction of domain.valuesSnapshot()) {
      const precedence = domain.precedence(interaction)
      const previous = next.get(interaction.sessionId)
      if (previous === undefined || precedence >= previous.precedence) {
        next.set(interaction.sessionId, { interaction, precedence })
      }
    }
  }
  const projected = new Map(
    [...next].map(([sessionId, value]) => [sessionId, value.interaction] as const),
  )
  if (samePendingInteractions(this.pendingSnapshot, projected)) return
  this.pendingSnapshot = projected
  notifySubscribers(this.pendingListeners, '[ui-session] pending interactions')
}
```
`ConversationContent.tsx:114-115` then reads `snapshot.get(sessionId)` for the **current** session only.
So an approval belonging to session B is simply not in the running session A's view.

**(b) Sidebar indication — a warning status dot on the owning session's row.**
`packages/client/ui-workspace/src/client/tree.ts:297-326`:
```ts
/** Keep navigation presentation independent from domain-owned interaction objects. */
function visiblePendingKind(kind: string | undefined): SessionPendingInteractionStatus | undefined {
  switch (kind) {
    case 'approval':
    case 'plan-review':
    case 'question':
      return kind
    default:
      return undefined
  }
}

function sessionNode(
  s: SessionSummary,
  descendants: ReadonlyMap<SessionId, SubagentDescendantSummary>,
  pendingInteractions: SessionPendingInteractions,
): SessionNode {
  const pendingInteraction = visiblePendingKind(pendingInteractions.get(s.id)?.kind)
  return {
    ...
    ...(pendingInteraction === undefined ? {} : { pendingInteraction }),
  }
}
```
Rendering — `packages/client/ui-workspace/src/client/rows/Rows.tsx:227-269`:
```tsx
/**
 * Session status presentation; pending interaction is primary and live activity
 * outranks completion reminders.
 */
function sessionStatuses(node, t): readonly [SessionStatus, ...SessionStatus[]] {
  …
  let pending: SessionStatus | undefined
  switch (node.pendingInteraction) {
    case 'approval':
      pending = { state: 'warning', label: t('status.waitingApproval') }
      break
    case 'plan-review':
      pending = { state: 'warning', label: t('status.planReview') }
      break
    case 'question':
      pending = { state: 'warning', label: t('status.waitingAnswer') }
      break
    case undefined: break
    /* v8 ignore next -- closed PendingInteractionStatus union */
    default: return assertNever(node.pendingInteraction)
  }
  if (pending !== undefined) return subagents === undefined ? [pending] : [pending, subagents]
  if (node.running) { … }
  …
}
```
Contextual warning label logic — `Rows.tsx:246-269`; when both a pending badge and subagent activity
exist, BOTH show (`[pending, subagents]`).

Labels — `packages/client/ui-workspace/src/client/locales.ts:57-59, 127-129`:
```ts
'status.waitingApproval': '等待审批',
'status.planReview': '计划待审',
'status.waitingAnswer': '等待回答',
…
'status.waitingApproval': 'Waiting for approval',
'status.planReview': 'Plan awaiting review',
'status.waitingAnswer': 'Waiting for answer',
```

**Behavior is a plain warning dot + screen-reader label — NOT a button.** `Rows.tsx:283` comment for the
sibling schedule indicator states the pattern: *"Non-interactive active-Schedule marker; the enclosing row
remains the only action."* The status dots (`Rows.tsx:271-281`):
```tsx
function SessionStatusDots({ statuses }: { statuses: readonly [SessionStatus, ...SessionStatus[]] }) {
  return (
    <>
      <StateDot state={statuses[0].state} />
      {statuses.map(status => (
        <span className={css.visuallyHidden} key={status.label}>{status.label}</span>
      ))}
    </>
  )
}
```
**So "clicking" the badge is not a thing: the user clicks the session row**, which navigates to that
session; the takeover then appears there. **[VERIFIED — there is no dedicated click handler for the badge.]**

Test that pins it — `packages/client/ui-workspace/tests/rows.client.spec.tsx:514-544`:
```tsx
it.each([
  ['approval', '等待审批'],
  ['plan-review', '计划待审'],
  ['question', '等待回答'],
] as const)('shows %s as warning ahead of the running state', (pendingInteraction, label) => {
  vi.useFakeTimers()
  try {
    const node: SessionNode = {
      id: sid(pendingInteraction), title: 'Needs input', blank: false,
      pendingInteraction, running: true, runningSubagentCount: 0, completed: false,
      hasActiveSchedule: false, updatedAt: 0,
    }
    const view = render(<SessionNodeItem node={node} currentId={undefined} now={0} onOpen={vi.fn()}
      onRename={vi.fn()} onFork={vi.fn()} onArchive={vi.fn()} t={t} />)
    const row = screen.getByRole('treeitem')
    expect(row.querySelector('[data-state="warning"]')).toBeTruthy()
    expect(row.querySelector('[data-state="ongoing"]')).toBeNull()
    expect(screen.getByText(label)).toBeTruthy()
    …
```
Note: `pendingInteraction` **outranks `running`** — a busy session waiting on approval shows *warning*,
not *ongoing*.

**Agent scoping.** The waterfall is Agent-scoped (`packages/interaction/user-approval/src/types.ts:76-90`):
```ts
'approval/request'(
  this: Scoped<Agent>,
  req: ApprovalRequestEvent,
  next: () => Promise<ApprovalOutcome>,
): Promise<ApprovalOutcome>
```
Documented: *"Scope-filtered dispatch (`@deepseek-ai/dsh-scope`): agent-scoped listeners receive only that agent."*
Only one answerer may claim; the rest receive nothing. Test — `tests/ui-approval.client.spec.tsx:200-209`:
```tsx
it('delegates an event that has no Agent scope', async () => {
  const bench = setupPlugin()
  const next = vi.fn(() => Promise.resolve<'unavailable'>('unavailable'))
  await expect(bench.listener.call(bench.ctx, { toolName: 'bash' }, next))
    .resolves.toBe('unavailable')
  expect(next).toHaveBeenCalledOnce()
  expect(bench.pending.getSnapshot()).toEqual([])
  expect(bench.register).toHaveBeenCalledOnce()
})
```

### 1.6 Sound / desktop notification for a pending approval [VERIFIED: NONE]

**There is no sound, no `Notification` API, no vibration, no title flash, and no favicon change
tied to a pending approval (or pending question) anywhere in the client packages.**

Evidence:
- A repo-wide grep for `Notification|playSound|AudioContext|desktop notification` across
  `packages/client` returns **only** unrelated hits: `processNotifications` local test counters in
  `ui-chat/tests/conversation-node-definitions.client.spec.ts` and `document.title` writes in
  `ui-layout`.
- `document.title` **is** written, but purely as the session title — it carries no pending state.
  `packages/client/ui-layout/src/client/DocumentTitle.tsx:24`:
  ```ts
  document.title = title === undefined ? productTitle : `${title} — ${productTitle}`
  ```
  Tests at `packages/client/ui-layout/tests/document-title.client.spec.tsx:38-80` and
  `app-frame.client.spec.tsx:184-247` assert the format `'Session title — Product'` and nothing about
  pending state.

**The only attention signal is the sidebar warning dot (§1.5b).** A Flutter port that adds sound/notification
would be *exceeding* the reference implementation, not matching it.

---

## 2. USER QUESTIONS

### 2.1 The exact request shape [VERIFIED]

`packages/interaction/user-questions/src/types.ts:6-48` — this is the wire type:
```ts
/** One selectable answer offered to the user. */
export interface AskUserQuestionOption {
  /** User-facing label. */
  label: string
  /** Optional extra context rendered by capable UIs. */
  description?: string
}

/**
 * A caller-declared presentation intent: the question IS this kind of
 * decision, so a UI that recognises the tag may present it as such instead of as a
 * generic option list. Tagged so further intents can be added; a UI that does
 * not know a tag renders the generic flow, and the answer encoding is identical
 * either way — an intent changes presentation only, never the protocol.
 */
export type AskUserQuestionIntent = {
  /** A plan submitted for review: `detail` is the plan markdown `ask()` requires, and the decision approves or declines it. */
  kind: 'plan-review'
  /**
   * The option label that approves the plan; every other option declines it.
   * Named rather than positional so no UI infers the verdict from option order.
   * An `approve` naming no option of its own question is rejected at `ask()`.
   */
  approve: string
}

/** One question in a user-questions request. */
export interface AskUserQuestionItem {
  /** Stable caller-provided question id, echoed in the answer. */
  id: string
  /** The question to display. */
  question: string
  /** Optional supporting detail rendered with the question but kept out of option labels. */
  detail?: string
  /** Optional short heading/group label. */
  header?: string
  /** Optional choices the UI can render as a menu. */
  options?: AskUserQuestionOption[]
  /** Whether more than one option may be selected. Defaults to single-select. */
  multiSelect?: boolean
  /** Optional presentation intent for capable UIs; absent asks for the generic option list. */
  intent?: AskUserQuestionIntent
}
```

Request envelope — `types.ts:66-74`:
```ts
/** Client-safe payload declared for the user-question answerer waterfall. */
export interface AskUserQuestionRequestEvent {
  /** Questions to display. */
  questions: AskUserQuestionItem[]
  /** Agent identity projected to the corresponding Client Context in transit. */
  agent?: Agent
  /** Cancellation lifetime of the pending request. */
  signal?: AbortSignal
}
```

Wire event — `types.ts:76-90`:
```ts
'user-questions/request'(
  this: Scoped<Agent>,
  request: AskUserQuestionRequestEvent,
  next: () => Promise<AskUserQuestionAnswer>,
): Promise<AskUserQuestionAnswer>
```

**Field summary:**

| Field | Type | Required | Rendering role |
|---|---|---|---|
| `id` | `string` | ✅ | Echoed in the answer; never displayed |
| `question` | `string` | ✅ | The card's `<h2>` title **and** its `aria-labelledby` target |
| `header` | `string?` | — | Small "eyebrow" line above the title |
| `detail` | `string?` | — | Markdown body rendered with `MarkdownText` inside the scroll region |
| `options` | `{label, description?}[]?` | — | Absent/empty ⇒ the question renders as a **pure free-text block** |
| `multiSelect` | `boolean?` | — | Default `false`. Switches radio→checkbox semantics |
| `intent` | `{kind:'plan-review', approve}`? | — | Presentation-only hint; see §2.5 |

**Model-facing tool schema** (what actually produces these) — `packages/interaction/tool-ask-user/src/index.ts:23-57`:
```ts
parameters: {
  questions: {
    type: 'array',
    required: true,
    description: 'Questions to ask the user before continuing.',
    items: {
      type: 'object',
      additionalProperties: true,
      properties: {
        id: { type: 'string', required: true, description: 'Stable id for this question; echoed in the answer.' },
        question: { type: 'string', required: true, description: 'The specific question to ask the user.' },
        header: {
          type: 'string',
          description: 'Optional short heading for the question, such as "Confirm" or "Choose Mode".',
        },
        options: {
          type: 'array',
          description: 'Optional choices to show the user. If you recommend one, put it first and append "(Recommended)" to that label.',
          items: {
            type: 'object',
            additionalProperties: true,
            properties: {
              label: { type: 'string', required: true, description: 'Short user-facing option label.' },
              description: { type: 'string', description: 'One sentence explaining the tradeoff or impact.' },
            },
          },
        },
        multi_select: {
          type: 'boolean',
          description: 'Whether the user may select more than one option. Defaults to false.',
        },
      },
    },
  },
},
```
⚠️ **Naming mismatch to port carefully:** the model writes **`multi_select`** (snake_case); the wire/UI type is
**`multiSelect`** (camelCase). Translation happens in the tool — `tool-ask-user/src/index.ts:87`:
```ts
...question.multi_select !== undefined ? { multiSelect: question.multi_select } : {},
```
Also note `intent` is **not** in the tool schema — only `plan-mode` sets it internally, bypassing the tool.

### 2.2 The exact `outcome` payload [VERIFIED]

**Same pattern as approvals: the client returns the object bare; the bridge wraps it into
`{kind:'result', value:{answers:[…]}}`.**

Types — `types.ts:50-64`:
```ts
/** Answer to one question. */
export interface AskUserQuestionAnswerItem {
  /** The answered question id. */
  id: string
  /** Selected option labels. May accompany custom text for a multi-select question. */
  selected: string[]
  /** Optional free-text "Other" answer. */
  custom?: string
}

/** The human's answer. */
export interface AskUserQuestionAnswer {
  /** Structured answers keyed by question id. */
  answers: AskUserQuestionAnswerItem[]
}
```
Re-exported by the client as `QuestionAnswer` — `packages/client/ui-user-questions/src/client/contract/slots.ts:17-18`:
```ts
/** One structured answer batch covering every question of the request. */
export type QuestionAnswer = AskUserQuestionAnswer
```

**The encoding function** — `packages/client/ui-user-questions/src/client/QuestionComposer.tsx:205-232`:
```tsx
const submitDrafts = (values: QuestionDraftAnswer[]): void => {
  const missing = values.findIndex(item => !completed(item))
  if (missing >= 0) {
    replaceProgress(missing, values)
    setError({ key: 'error.incomplete' })
    return
  }
  const answer: QuestionAnswer = {
    answers: questions.map((item, itemIndex) => {
      const value = values[itemIndex] as QuestionDraftAnswer
      if (value.skipped) return { id: item.id, selected: [] }
      const custom = value.custom.trim()
      return {
        id: item.id,
        selected: custom === '' || item.multiSelect === true ? value.selected : [],
        ...(custom === '' ? {} : { custom }),
      }
    }),
  }
  setBusy('answer')
  setError(null)
  void pending.answer(answer)
    .then(() => { actions.clear(pending.key) })
    .catch((cause: unknown) => {
      setBusy(null)
      setError({ text: cause instanceof Error ? cause.message : String(cause) })
    })
}
```

**The three encoding rules, precisely:**

| Rule | Condition | Resulting item |
|---|---|---|
| **Skipped** | `value.skipped === true` | `{ id, selected: [] }` — `custom` **omitted**, even if text exists |
| **Single-select + custom text present** | `multiSelect !== true` and `custom.trim() !== ''` | `{ id, selected: [], custom: "<text>" }` — **`selected` is FORCED EMPTY** (custom overrides) |
| **Multi-select** | `multiSelect === true` | `{ id, selected: [...labels] }` and, if text present, **also** `custom: "<text>"` — **both coexist** |
| **Multi-select, no text** | `multiSelect === true`, `custom === ''` | `{ id, selected: [...labels] }` — `custom` key absent |
| **Single-select, no text** | `multiSelect !== true`, `custom === ''` | `{ id, selected: [...oneLabel] }` — `custom` key absent |

**Key detail: `custom` is committed as an ABSENT KEY when empty** — `...(custom === '' ? {} : { custom })`.
It is never `custom: ""` and never `custom: undefined`. This matters for JSON equivalence.

**Key detail: `custom.trim()` is applied.** Leading/trailing whitespace is stripped before the emptiness
test and before sending. Interior newlines survive verbatim (test at `:333-337` asserts a multi-line value
round-trips).

**Exact wire payloads:**

| Scenario | `outcome.value` |
|---|---|
| One single-select question, option "Fast" picked | `{"answers":[{"id":"mode","selected":["Fast"]}]}` |
| One single-select question, free text "Custom" typed | `{"answers":[{"id":"mode","selected":[],"custom":"Custom"}]}` |
| One multi-select question, "A"+"B" checked, no text | `{"answers":[{"id":"sig","selected":["A","B"]}]}` |
| One multi-select question, "A" checked + text "other" | `{"answers":[{"id":"sig","selected":["A"],"custom":"other"}]}` |
| One skipped question | `{"answers":[{"id":"q","selected":[]}]}` |
| Whole batch | `{"answers":[…one item per question, in request order…]}` |

Full wire envelope: `{"clientId":"<uuid>","eventId":"<uuid>","outcome":{"kind":"result","value":{"answers":[…]}}}`

**Every question in the request gets exactly one answer item, in request order** —
`questions.map((item, itemIndex) => …)` at `:213`. `questions.map` preserves order; the answer array
is parallel to the request array.

**Selected values are the RAW labels, not display labels.** The recommendation-suffix stripping is
presentation-only:
- `QuestionComposer.tsx:325-330` renders `display.label` (stripped) but calls `choose(option.label)` (**raw**)
- `QuestionComposer.tsx:320` — `const selected = draft.selected.includes(option.label)` (**raw matching**)

Proved by the test — `tests/user-questions-composer.client.spec.tsx:220-224`:
```tsx
expect(answer).toHaveBeenCalledWith(answerBatch([
  { id: 'profile', selected: ['工程落地型 (Recommended)'] },   // ← suffix PRESERVED in the answer
  { id: 'detail', selected: [], custom: '要能独立排查线上问题' },
  { id: 'signals', selected: ['系统设计', '代码质量', '产品判断'], custom: '沟通能力' },
]))
```
while the UI showed `工程落地型` + a `推荐` badge (`:185-186`).

**The "Recommended" convention** — `QuestionComposer.tsx:25-35`:
```tsx
/**
 * Split the conventional recommendation suffix without changing the answer value.
 * @param label - Original option label returned if selected.
 * @returns Display label plus recommendation state.
 */
export function parseRecommendedLabel(label: string): { label: string; recommended: boolean } {
  const suffix = /\s*(?:\((?:recommended|推荐)\)|（(?:recommended|推荐)）)\s*$/i
  return suffix.test(label)
    ? { label: label.replace(suffix, ''), recommended: true }
    : { label, recommended: false }
}
```
Recognizes ASCII `(...)` and fullwidth `（...）`, case-insensitive, in English or Chinese. Tests —
`tests/user-questions-composer.client.spec.tsx:480-487`:
```tsx
describe('parseRecommendedLabel', () => {
  it('recognizes English and Chinese suffixes without changing ordinary labels', () => {
    expect(parseRecommendedLabel('Fast (Recommended)')).toEqual({ label: 'Fast', recommended: true })
    expect(parseRecommendedLabel('稳妥（推荐）')).toEqual({ label: '稳妥', recommended: true })
    expect(parseRecommendedLabel('稳妥 (推荐)')).toEqual({ label: '稳妥', recommended: true })
    expect(parseRecommendedLabel('Plain')).toEqual({ label: 'Plain', recommended: false })
  })
})
```
The badge text is locale key `option.recommended` = `推荐` / `Recommended` (`locales.ts:12,34`).

**The model's own convention is stated in the tool description** — `tool-ask-user/src/index.ts:40`:
> `'Optional choices to show the user. If you recommend one, put it first and append "(Recommended)" to that label.'`

### 2.3 Validation gates, partial submission, skip [VERIFIED]

**Gates (all client-side, plus Host-side re-validation):**

**Gate 1 — Escape/Enter on the current question requires it be answered.**
`QuestionComposer.tsx:234-245`:
```tsx
const continueFlow = (): void => {
  if (!answered(draft)) {
    setError({ key: 'error.unanswered' })
    return
  }
  if (index < questions.length - 1) {
    replaceProgress(index + 1, drafts)
    setError(null)
    return
  }
  submitDrafts(drafts)
}
```
with `:200-203`:
```tsx
const answered = (item: QuestionDraftAnswer): boolean =>
  item.selected.length > 0 || item.custom.trim() !== ''

const completed = (item: QuestionDraftAnswer): boolean => answered(item) || item.skipped
```
"Answered" = **≥1 selected label OR non-blank custom text.** No other way to pass.

**Gate 2 — every question must be `completed` (answered or explicitly skipped) at submit.**
`QuestionComposer.tsx:205-211`:
```tsx
const missing = values.findIndex(item => !completed(item))
if (missing >= 0) {
  replaceProgress(missing, values)
  setError({ key: 'error.incomplete' })
  return
}
```
On failure it **jumps the pager to the first offending question** (`replaceProgress(missing, …)`) and
shows `请先完成这道问题。` / `Please complete this question first.`

**Gate 3 — the primary button is disabled until the current question is answered.**
`QuestionComposer.tsx:426-433`:
```tsx
<Button
  variant="primary"
  disabled={busy !== null || !answered(draft)} onClick={continueFlow}
>
  {busy === 'answer'
    ? t('submitting')
    : index === questions.length - 1 ? t('submit') : t('action.next')}
</Button>
```

⚠️ **Note the asymmetry:** the primary button's `disabled` uses `answered` (which does **not** count
`skipped`), but `continueFlow` is *also* blocked by `answered`. So the **button stays disabled even after
you Skip** — skipping auto-advances/submits, so you never need the button on a skipped question.
**[VERIFIED — `skipQuestion` at `:266-276` immediately advances or submits.]**

**"Skip" — the escape hatch.** `QuestionComposer.tsx:266-276`:
```tsx
const skipQuestion = (): void => {
  const nextDrafts = drafts.map((item, itemIndex) => itemIndex === index
    ? { selected: [], custom: '', skipped: true }
    : item)
  replaceProgress(index < questions.length - 1 ? index + 1 : index, nextDrafts)
  setError(null)
  if (index < questions.length - 1) {
    return
  }
  submitDrafts(nextDrafts)
}
```
Skip **clears that question's draft**, marks it skipped, and:
- advances if not last, or
- **auto-submits the whole batch if it IS the last question.**

The Skip button is always enabled (unless busy) — `:423-425`:
```tsx
<Button variant="outline" disabled={busy !== null} onClick={skipQuestion}>
  {t('action.skip')}
</Button>
```
Label `跳过` / `Skip` (`locales.ts:14,36`).

**Partial submission is IMPOSSIBLE. Skip is the only sanctioned partial.** A skipped question emits
`{id, selected: []}`.

Test — `tests/user-questions-composer.client.spec.tsx:243-259`:
```tsx
it('skips individual questions without discarding earlier answers', () => {
  const { carrier, answer } = wait()
  render(<QuestionComposer matched={carrier} {...kit} />)

  expect((screen.getByText('下一题').closest('button') as HTMLButtonElement).disabled).toBe(true)
  fireEvent.click(screen.getByRole('radio', { name: '研究潜力型' }))
  expect(screen.getByText('2 / 3')).toBeTruthy()
  fireEvent.click(screen.getByRole('button', { name: '跳过' }))
  expect(screen.getByText('3 / 3')).toBeTruthy()
  fireEvent.click(screen.getByRole('button', { name: '跳过' }))

  expect(answer).toHaveBeenCalledWith(answerBatch([
    { id: 'profile', selected: ['研究潜力型'] },
    { id: 'detail', selected: [] },      // ← skipped
    { id: 'signals', selected: [] },     // ← skipped, and this SUBMITTED the batch
  ]))
})
```

**What happens if the user closes without answering → `pending.cancel()`.**
`QuestionComposer.tsx:168-177`:
```tsx
const cancelFlow = (): void => {
  setBusy('cancel')
  setError(null)
  void pending.cancel()
    .then(() => { actions.clear(pending.key) })
    .catch((cause: unknown) => {
      setBusy(null)
      setError({ text: cause instanceof Error ? cause.message : String(cause) })
    })
}
```
`contract/slots.ts:182-189`:
```ts
/** Reject the Host waterfall because the user closed the question. */
cancel(): Promise<void> {
  return settlePendingComposer(() => {
    this.finish(() => {
      this.#reject(questionError('the user cancelled ask_user_question', 'ASK_CANCELLED'))
    })
  }, 'pending question cancellation failed')
}
```
with `slots.ts:100-106`:
```ts
/** Create a wire-preserved user-question rejection. */
function questionError(message: string, code: 'ASK_ABORTED' | 'ASK_CANCELLED'): Error {
  const error = new Error(message) as Error & { code: string }
  error.name = 'UserQuestionError'
  error.code = code
  return error
}
```

**The wire value is `{kind:'rejected', error:{name:'UserQuestionError', code:'ASK_CANCELLED',
message:'the user cancelled ask_user_question'}}`** — `error.code` survives because
`projectRemoteEventRejection` retains `code` (`packages/api/gateway/src/stream-protocol.ts:179-191`):
```ts
export function projectRemoteEventRejection(reason: unknown): RemoteEventRejection {
  const record = typeof reason === 'object' && reason !== null ? reason : undefined
  const name = stringProperty(record, 'name') ?? 'Error'
  const message = stringProperty(record, 'message') ?? String(reason)
  const code = stringProperty(record, 'code')
  const details = record === undefined ? undefined : Reflect.get(record, 'details') as unknown
  return {
    name,
    message,
    ...(code === undefined ? {} : { code }),
    ...(details === undefined || !isRemoteJsonValue(details) ? {} : { details }),
  }
}
```

On the Host this surfaces as a `UserQuestionError` with code `ASK_CANCELLED`
(`packages/interaction/user-questions/src/index.ts:34-39, 53-62`), and consumers special-case it.
Plan mode does — `packages/plan/plan-mode/src/index.ts:319-330`:
```ts
}).catch((cause: unknown) => {
  // A dismissed review is not a failed one: the user took the turn back
  // to say something they do not cover. Say so, because the
  // generic channel message names ask_user_question, which the model
  // never called. …
  if (cause instanceof UserQuestionError && cause.code === 'ASK_CANCELLED') {
    throw new Error('The user dismissed the plan review to speak instead; '
      + 'stay in plan mode, stop here, and wait for their message.')
  }
  throw cause
})
```

**Cancel failure is recoverable and surfaced.** Test —
`tests/user-questions-composer.client.spec.tsx:340-353`:
```tsx
it('surfaces cancellation failures and re-arms the controls', async () => {
  const { carrier, cancel } = wait()
  cancel
    .mockRejectedValueOnce(new Error('第一次取消失败'))
    .mockRejectedValueOnce(new Error('第二次取消失败'))
  render(<QuestionComposer matched={carrier} {...kit} />)

  fireEvent.click(screen.getByRole('button', { name: '放弃整组问题' }))
  expect(await screen.findByText('第一次取消失败')).toBeTruthy()
  expect(screen.getByRole<HTMLButtonElement>('button', { name: '跳过' }).disabled).toBe(false)

  fireEvent.click(screen.getByRole('button', { name: '放弃整组问题' }))
  expect(await screen.findByText('第二次取消失败')).toBeTruthy()
})
```
Note: the `busy` flag is set to `'cancel'` in the approval panel too but that's a different file.
In `QuestionFlow`, `busy === 'cancel'` does **not** change the button label (only `'answer'` does, → `正在提交…`).

**Answer-rejection recovery** — `tests/user-questions-composer.client.spec.tsx:355-384` shows the error
message renders and the submit button re-enables; a second failure with a non-Error value stringifies:
```tsx
expect(await screen.findByText('网络中断')).toBeTruthy()
expect(screen.getByRole<HTMLButtonElement>('button', { name: '提交' }).disabled).toBe(false)

fireEvent.click(screen.getByRole('button', { name: '提交' }))
expect(await screen.findByText('字符串错误')).toBeTruthy()
```
(the `String(cause)` fallback at `:230`).

**Validation feedback copy** — `locales.ts:5-6, 27-28`:
```ts
'error.incomplete': '请先完成这道问题。',
'error.unanswered': '请选择一个选项或填写自定义答案。',
…
'error.incomplete': 'Please complete this question first.',
'error.unanswered': 'Please select an option or enter a custom answer.',
```
Rendered in `role="status"` (`QuestionComposer.tsx:419-421`) — a polite live region:
```tsx
<div className={css.feedback} role="status">
  {error === null ? null : 'key' in error ? t(error.key) : error.text}
</div>
```
Validation errors are stored as **locale keys** and translated at render (so a language switch re-renders
them); runtime failures are stored as literal strings and pass through untranslated
(`QuestionComposer.tsx:17-23`).

Test of the gates — `tests/user-questions-composer.client.spec.tsx:281-301`:
```tsx
it('shows the inline custom input, reports missing answers, and supports pager navigation', () => {
  const { carrier, answer } = wait()
  render(<QuestionComposer matched={carrier} {...kit} />)

  expect(screen.getByPlaceholderText('输入你的答案')).toBeTruthy()
  fireEvent.click(screen.getByRole('radio', { name: '工程落地型' }))
  const emptyCustom = screen.getByPlaceholderText('输入你的答案')
  fireEvent.keyDown(emptyCustom, { key: 'Enter', shiftKey: true })
  expect(screen.getByText('2 / 3')).toBeTruthy()          // Shift+Enter does NOT advance
  fireEvent.keyDown(emptyCustom, { key: 'Enter' })
  expect(screen.getByText('请选择一个选项或填写自定义答案。')).toBeTruthy()  // ← error.unanswered

  fireEvent.click(screen.getByLabelText('下一题'))
  fireEvent.click(screen.getByRole('checkbox', { name: '产品判断' }))
  fireEvent.click(screen.getByRole('button', { name: '提交' }))
  expect(screen.getByText('请先完成这道问题。')).toBeTruthy()   // ← error.incomplete
  expect(screen.getByText('2 / 3')).toBeTruthy()            // ← jumped back to the offender
  fireEvent.click(screen.getByLabelText('上一题'))
  expect(screen.getByText('1 / 3')).toBeTruthy()
  expect(answer).not.toHaveBeenCalled()
})
```

### 2.4 Rendering: single-select vs multi-select vs freeform [VERIFIED]

**One question at a time, paginated. Not a long scrolling form.**

Card anatomy — `QuestionComposer.tsx:278-310`:
```tsx
<div className={css.frame} data-question-key={pending.key}>
  <section
    className={clsx(css.card, minimized && css.cardMinimized)}
    aria-labelledby={`question-${pending.key}-${String(index)}`}
  >
    <header className={css.header}>
      <div className={css.headingBlock}>
        {question.header !== undefined && <div className={css.eyebrow}>{question.header}</div>}
        <h2 className={css.title} id={`question-${pending.key}-${String(index)}`}>
          {question.question}
        </h2>
      </div>
      <div className={css.headerActions}>
        <button … aria-label={t(minimized ? 'nav.maximize' : 'nav.minimize')}
          aria-expanded={!minimized} … onClick={() => { setMinimized(current => !current) }}>
          {minimized ? <IconChevronUpOutline14 /> : <IconChevronDownOutline14 />}
        </button>
        <button … aria-label={t('nav.cancel')} … onClick={cancelFlow}>
          <IconCloseOutline16 />
        </button>
      </div>
    </header>
    …
```

| Aspect | Single-select | Multi-select |
|---|---|---|
| Container role | `role="radiogroup"` | `role="group"` |
| Option role | `role="radio"` | `role="checkbox"` |
| `aria-checked` | `selected` | `selected` |
| Marker | **`<span className={css.number}>{optionIndex + 1}</span>`** (ordinal) | checkbox square with `<IconCheckOutline14 size={12} />` when checked |
| Selected style | `css.optionSelected` on the button | checkbox fill (`css.checkboxChecked`) |
| Toggle | `return { selected: [label], custom: '', skipped: false }` — **replaces** | toggle in/out of array — **accumulates** |
| Auto-advance | **YES** — jumps to next question | **NO** |

The container — `QuestionComposer.tsx:318`:
```tsx
<div className={css.options} role={question.multiSelect === true ? 'group' : 'radiogroup'}>
```
The option button — `QuestionComposer.tsx:322-356`:
```tsx
<button
  type="button" key={`${option.label}-${String(optionIndex)}`}
  className={clsx(css.option, selected && question.multiSelect !== true && css.optionSelected)}
  role={question.multiSelect === true ? 'checkbox' : 'radio'}
  aria-checked={selected}
  aria-label={display.label}
  disabled={busy !== null}
  onClick={() => { choose(option.label) }}
  onKeyDown={(event) => {
    if (event.key !== 'Enter' || !drafts.every(completed)) return
    event.preventDefault()
    submitDrafts(drafts)
  }}
>
  {question.multiSelect === true
    ? (
      <span className={clsx(css.checkbox, selected && css.checkboxChecked)} aria-hidden="true">
        {selected && <IconCheckOutline14 size={12} />}
      </span>
    )
    : <span className={css.number}>{optionIndex + 1}</span>}
  <span className={css.optionCopy}>
    <span className={css.optionLine}>
      <span className={css.optionLabel}>{display.label}</span>
      {display.recommended && (
        <span className={css.badge}>{t('option.recommended')}</span>
      )}
      {option.description !== undefined && (
        <span className={css.description}>{option.description}</span>
      )}
    </span>
  </span>
</button>
```
ℹ️ **Single-select options are numbered `1, 2, 3…` from `optionIndex + 1`** — this implies a keyboard
shortcut affordance, but **the code registers no digit key handler** — the number is decorative.
**[VERIFIED by absence.]** `aria-label` is `display.label` (the suffix-stripped label) while the visible
text is also `display.label` — the raw label only lives in state.
Note the `aria-label` does **not** include `description`; `description` renders as a sibling span.

**Selection toggling** — `QuestionComposer.tsx:188-198`:
```tsx
const choose = (label: string): void => {
  updateDraft((current) => {
    if (question.multiSelect === true) {
      const selected = current.selected.includes(label)
        ? current.selected.filter(item => item !== label)
        : [...current.selected, label]
      return { ...current, selected, skipped: false }
    }
    return { selected: [label], custom: '', skipped: false }
  }, question.multiSelect !== true && index < questions.length - 1 ? index + 1 : index)
}
```
**Auto-advance rule:** single-select AND not the last question → go to `index + 1`. Otherwise stay.
Multi-select never auto-advances. Note it also **clears `custom`** on a single-select pick (exclusivity).

**Freeform — two shapes.**
`QuestionComposer.tsx:359-397`:
```tsx
{hasOptions
  ? (
    <div className={clsx(css.customRow, draft.custom !== '' && css.customRowActive)}>
      {question.multiSelect === true
        ? (
          <span className={clsx(css.checkbox, draft.custom !== '' && css.checkboxChecked)} aria-hidden="true">
            {draft.custom !== '' && <IconCheckOutline14 size={12} />}
          </span>
        )
        : (
          <span className={css.number} aria-hidden="true">
            <IconEditOutline16 size={12} />
          </span>
        )}
      <AnswerField
        variant="inline"
        value={draft.custom}
        disabled={busy !== null}
        placeholder={t('custom.placeholder')}
        onChange={draftCustom}
        onKeyDown={continueFromCustom}
      />
    </div>
  )
  : (
    <AnswerField
      autoFocus={!focusedQuestions.current.has(index)}
      variant="block"
      value={draft.custom}
      disabled={busy !== null}
      placeholder={t('custom.placeholder')}
      onFocus={() => { focusedQuestions.current.add(index) }}
      onChange={draftCustom}
      onKeyDown={continueFromCustom}
    />
  )}
```
where `const hasOptions = (question.options?.length ?? 0) > 0` (`:162`).

| Variant | When | Marker | Notes |
|---|---|---|---|
| **`inline`** — an extra "Other" row after the options | question **has** options | multi-select ⇒ checkbox that fills when text is present; single-select ⇒ a pencil `IconEditOutline16` icon | `customRowActive` class when non-empty |
| **`block`** — the whole answer area | question has **no** options | none | `autoFocus` on first presentation of this index |

**Placeholder: `输入你的答案` / `Type your answer`** (`locales.ts:13, 35`).

The field is an **auto-growing `<textarea>`** with a hidden height mirror —
`QuestionComposer.tsx:64-97` (doc comment omitted for brevity):
```tsx
function AnswerField(props: AnswerFieldProps) {
  return (
    <div className={clsx(css.field, props.variant === 'inline' ? css.customInline : css.customBlock)}>
      <div aria-hidden className={css.fieldMirror}>{`${props.value}\n`}</div>
      <textarea
        autoFocus={props.autoFocus}
        className={css.fieldInput}
        value={props.value}
        disabled={props.disabled}
        rows={1}
        placeholder={props.placeholder}
        onFocus={props.onFocus}
        onChange={props.onChange}
        onKeyDown={props.onKeyDown}
      />
    </div>
  )
}
```
`rows={1}` + a mirror div containing `value + '\n'` sizes the grid row so the textarea grows with soft wraps.
Test — `tests/user-questions-composer.client.spec.tsx:303-338`:
```tsx
it('answers over multiple lines: both fields grow with the draft and keep Shift+Enter a newline', () => {
  …
  const inline = screen.getByPlaceholderText('输入你的答案')
  expect(inline.tagName).toBe('TEXTAREA')

  const multiline = '第一行\n第二行'
  fireEvent.change(inline, { target: { value: multiline } })
  // The hidden height ruler carries the draft plus the trailing newline the
  // textarea's own last line needs, so the box is as tall as the answer.
  expect(inline.previousElementSibling?.textContent).toBe(`${multiline}\n`)
  // Shift+Enter belongs to the field, never to the flow.
  fireEvent.keyDown(inline, { key: 'Enter', shiftKey: true })
  expect(screen.getByText('1 / 3')).toBeTruthy()
  …
```

**Custom-text rules** — `QuestionComposer.tsx:250-264`:
```tsx
const draftCustom = (event: ChangeEvent<HTMLTextAreaElement>): void => {
  const value = event.target.value
  updateDraft(current => ({
    ...current,
    selected: question.multiSelect === true ? current.selected : [],
    custom: value,
    skipped: false,
  }))
}

const continueFromCustom = (event: KeyboardEvent<HTMLTextAreaElement>): void => {
  if (event.key !== 'Enter' || event.shiftKey || isComposing(event)) return
  event.preventDefault()
  continueFlow()
}
```
- **Single-select: typing CLEARS the selection** (`selected: []`) — mutual exclusivity.
- **Multi-select: typing PRESERVES the selection.**
- **Enter** in the field = continue/submit. **Shift+Enter** = newline. **IME composition Enter is ignored.**

IME guard — `QuestionComposer.tsx:37-42`:
```tsx
/** Return whether a text-field key event belongs to an active IME composition. */
function isComposing(event: KeyboardEvent<HTMLTextAreaElement>): boolean {
  // keyCode 229 is the legacy IME-composition signal engines emit without isComposing.
  // oxlint-disable-next-line typescript/no-deprecated
  return event.nativeEvent.isComposing || event.nativeEvent.keyCode === 229
}
```
Test — `tests/user-questions-composer.client.spec.tsx:261-279`:
```tsx
it('keeps IME Enter inside the custom input until composition finishes', () => {
  …
  fireEvent.keyDown(custom, { key: 'Enter', isComposing: true })
  expect(screen.getByText('2 / 3')).toBeTruthy()
  expect(answer).not.toHaveBeenCalled()

  fireEvent.keyDown(custom, { key: 'Enter', keyCode: 229 })
  expect(screen.getByText('2 / 3')).toBeTruthy()
  expect(answer).not.toHaveBeenCalled()

  fireEvent.keyDown(custom, { key: 'Enter' })
  expect(screen.getByText('3 / 3')).toBeTruthy()
})
```

**Detail (markdown) rendering** — `QuestionComposer.tsx:315-317`:
```tsx
{question.detail !== undefined && (
  <div className={css.detail}><MarkdownText text={question.detail} labels={markdownLabels} /></div>
)}
```
Renders via the shared assistant-output markdown primitive with GFM, inside `data-question-scroll`.
Test at `:187-191` asserts the detail is inside the `[data-question-scroll]` region while the "下一题"
button is outside it:
```tsx
const detail = screen.getByText('按当前空缺岗位的优先级选择。')
const scrollRegion = detail.closest('[data-question-scroll]')
expect(scrollRegion).toBeTruthy()
expect(scrollRegion?.contains(screen.getByRole('radio', { name: /工程落地型/ }))).toBe(true)
expect(scrollRegion?.contains(screen.getByText('下一题').closest('button'))).toBe(false)
```
i.e. **the header and footer stay fixed; only detail + options scroll** (`data-question-scroll`).

**Pager / footer** — `QuestionComposer.tsx:401-435`:
```tsx
<footer className={css.footer}>
  <div className={css.pager}>
    <button … aria-label={t('nav.prev')}
      disabled={index === 0 || busy !== null}
      onClick={() => { replaceProgress(index - 1, drafts); setError(null) }}>
      <IconChevronLeftOutline14 />
    </button>
    <span className={css.progress}>{index + 1} / {questions.length}</span>
    <button … aria-label={t('nav.next')}
      disabled={index === questions.length - 1 || busy !== null}
      onClick={() => { replaceProgress(index + 1, drafts); setError(null) }}>
      <IconChevronRightOutline14 />
    </button>
  </div>
  <div className={css.feedback} role="status">…</div>
  <div className={css.footerActions}>
    <Button variant="outline" disabled={busy !== null} onClick={skipQuestion}>{t('action.skip')}</Button>
    <Button variant="primary" disabled={busy !== null || !answered(draft)} onClick={continueFlow}>
      {busy === 'answer' ? t('submitting') : index === questions.length - 1 ? t('submit') : t('action.next')}
    </Button>
  </div>
</footer>
```
Progress text is `"${index + 1} / ${questions.length}"` — e.g. `2 / 3`. Locale keys
`nav.prev`/`nav.next` = `上一题`/`下一题` (prev/next chevrons), `action.next` = `下一题` (button),
`action.skip` = `跳过`.
⚠️ `nav.next` and `action.next` are **different keys with the same visible text** — one is an icon
`aria-label`, the other a button label.

**Minimize** — `:293-301`, `:312`. Collapsing hides everything below the header (`{!minimized && (…)}`),
leaving the `header` (eyebrow + title) and both header buttons. `aria-expanded={!minimized}`,
label flips `nav.minimize`/`nav.maximize` (`收起问题卡片`/`展开问题卡片`).
Test at `:440-454`. Drafts survive collapse (`:456-477`).

**Body scroll region keeps the header/footer fixed** — asserted at `:191`.

### 2.5 The plan-review presentation intent [VERIFIED]

A single question carrying `intent: {kind:'plan-review', approve}` renders a **different card**:
a decision card instead of a quiz. This is used by plan mode —
`packages/plan/plan-mode/src/index.ts:302-318`:
```ts
const answer = await interaction.ask({
  questions: [{
    id: REVIEW_ID,
    header: 'Plan review',
    question: 'Approve this plan and leave plan mode?',
    detail: args.plan,
    options: [
      { label: APPROVE_LABEL, description: 'Leave plan mode; the plan is carried out from the next step.' },
      { label: KEEP_PLANNING_LABEL, description: 'Stay in plan mode; feedback goes back to the model.' },
    ],
    // Presentation only: a capable UI renders the plan as a review
    // decision instead of a generic question, and answers with one of
    // the labels above either way.
    intent: { kind: 'plan-review', approve: APPROVE_LABEL },
  }],
  agent,
  signal: exec.signal,
})
```

**Election predicate** — `contract/slots.ts:77-96`:
```ts
export function planReviewOf(questions: readonly QuestionItem[]): PlanReview | undefined {
  if (questions.length !== 1) return undefined
  // Length-checked above; the index read is the narrowing tax, not a guess.
  const question = questions[0] as QuestionItem
  const intent = question.intent
  if (intent?.kind !== 'plan-review' || question.detail === undefined) return undefined
  if (question.multiSelect === true) return undefined
  const options = question.options ?? []
  if (options.length > 2) return undefined
  const approve = options.find(option => option.label === intent.approve)
  if (approve === undefined) return undefined
  const decline = options.find(option => option.label !== intent.approve)
  return {
    id: question.id,
    question: question.question,
    plan: question.detail,
    approve,
    ...(decline === undefined ? {} : { decline }),
  }
}
```
Doc comment (`slots.ts:59-76`): the card claims a request only when it can send every answer the request
allows; anything else falls to the generic flow. Tests at `tests/plan-review-panel.client.spec.tsx:183-204`
enumerate all seven rejection cases (empty batch, >1 question, no intent, no detail, approve names no option,
no options, third option, multi-select).

**The card** — `PlanReviewPanel.tsx:44-86`:
```tsx
const decide = (label: string): void => {
  settle(() => pending.answer({ answers: [{ id: review.id, selected: [label] }] }))
}
const decline = review.decline

return (
  <div className={css.frame} data-plan-review-key={pending.key}>
    <section className={css.card} aria-label={review.question}>
      <div className={css.strip}>
        <span className={css.dot} />
        {t('plan.header')}
      </div>
      <div className={css.body} data-plan-review-scroll>
        <MarkdownText text={review.plan} labels={markdownLabels} />
      </div>
      <div className={css.footer}>
        <div className={css.feedback} role="status">{error}</div>
        <div className={css.actions}>
          <Button
            variant="ghost" className={css.discuss} icon={<IconEditOutline16 size={14} />}
            disabled={busy} onClick={() => { settle(() => pending.cancel()) }}
          >
            {t('plan.discuss')}
          </Button>
          {decline !== undefined && (
            <Button
              variant="outline" {...tooltip(decline.description)}
              disabled={busy} onClick={() => { decide(decline.label) }}
            >
              {t('plan.decline')}
            </Button>
          )}
          <Button
            variant="primary" {...tooltip(review.approve.description)}
            disabled={busy} onClick={() => { decide(review.approve.label) }}
          >
            {t('plan.approve')}
          </Button>
        </div>
      </div>
    </section>
  </div>
)
```

Three actions, left→right — `locales.ts:17-19, 38-40`:

| Position | Locale key | zh | en | Variant | Wire effect |
|---|---|---|---|---|---|
| 1 (left) | `plan.discuss` | `去聊天里说` | `Chat about it` | `ghost` + pencil icon | `cancel()` → `{kind:'rejected', error:{name:'UserQuestionError', code:'ASK_CANCELLED', …}}` |
| 2 (middle) | `plan.decline` | `拒绝` | `Refuse` | `outline` | `answer({answers:[{id, selected:[decline.label]}]})` — **hidden when no decline option exists** |
| 3 (right) | `plan.approve` | `确认执行` | `Approve` | `primary` | `answer({answers:[{id, selected:[approve.label]}]})` |

⚠️ **The approve/decline buttons do NOT show the asker's label text.** They show the locale copy
(`Approve`/`Refuse`/`确认执行`/`拒绝`), while the *answer* sends the **asker's** label
(`decide(decline.label)` / `decide(review.approve.label)`). The asker's label appears only in the
`title` tooltip if a `description` exists (`tooltip()` at `:17-19`; test `:258-267` asserts the absence
of `title` when there's no description, and `:232` asserts the presence).
Confirming test — `tests/plan-review-panel.client.spec.tsx:227-248`:
```tsx
it('answers with the asker\'s approve label and keeps its description as the tooltip', () => {
  const { carrier, answer } = wait()
  render(<QuestionComposer matched={carrier} {...kit} />)

  const approve = screen.getByRole('button', { name: zh['plan.approve'] })
  expect(approve.getAttribute('title')).toBe('Leave plan mode; the plan is carried out from the next step.')
  fireEvent.click(approve)
  expect(answer).toHaveBeenCalledWith(decision('Approve'))
  // One-shot: every action locks until the host's resolved frame lands.
  expect(approve.hasAttribute('disabled')).toBe(true)
  expect(screen.getByRole('button', { name: zh['plan.decline'] }).hasAttribute('disabled')).toBe(true)
  fireEvent.click(approve)
  expect(answer).toHaveBeenCalledTimes(1)
})
```
Note `decision(label)` at `:163`:
```tsx
const decision = (label: string) => ({ answers: [{ id: 'plan-review', selected: [label] }] })
```

**Strip + markdown body, no quiz chrome** — `tests/plan-review-panel.client.spec.tsx:208-225`:
```tsx
it('renders the plan under a review strip, with none of the quiz affordances', () => {
  …
  expect(screen.getByText(zh['plan.header'])).toBeTruthy()
  expect(screen.getByRole('heading', { name: 'Ship the picker' })).toBeTruthy()
  expect(screen.getByText('render the rows')).toBeTruthy()
  expect(screen.getByLabelText('Approve this plan and leave plan mode?')).toBeTruthy()
  // No pager, no numbered options, no skip, no custom answer.
  expect(screen.queryByText('1 / 1')).toBeNull()
  expect(screen.queryByRole('radio')).toBeNull()
  expect(screen.queryByText(zh['action.skip'])).toBeNull()
  expect(screen.queryByRole('textbox')).toBeNull()
})
```
**`aria-label` on the section = the question text** (`PlanReviewPanel.tsx:51`), so the card is announced
by the question rather than reading like a test item.

**One-shot locking** — `PlanReviewPanel.tsx:34-43`:
```tsx
const [busy, setBusy] = useState(false)
const [error, setError] = useState<string | null>(null)
const settle = (send: () => Promise<void>): void => {
  setBusy(true)
  setError(null)
  void send().catch((cause: unknown) => {
    setBusy(false)
    setError(cause instanceof Error ? cause.message : String(cause))
  })
}
```
All three buttons share the single `busy` flag → clicking any locks all three. Failure re-arms all three
and shows the raw message in `role="status"` (`:60`). Test `:279-302`:
```tsx
it('re-arms the actions and says why when the decision does not land', async () => {
  …
  answer.mockRejectedValue(new Error('question response rejected: not-pending'))
  fireEvent.click(screen.getByRole('button', { name: zh['plan.approve'] }))
  const failure = await screen.findByText('question response rejected: not-pending')
  expect(failure.getAttribute('role')).toBe('status')
  expect(screen.getByRole('button', { name: zh['plan.approve'] }).hasAttribute('disabled')).toBe(false)
```
Note: unlike the approval panel, `PlanReviewPanel` shows the error text; it also has no minimize toggle.
Its decline-answer encoding includes **no `custom`** — `{ id, selected: [label] }` only.

**Host-side re-validation.** `plan-mode` re-checks the answer rather than trusting the UI —
`plan-mode/src/index.ts:336-343`:
```ts
const reviewItems = answer.answers.filter(entry => entry.id === REVIEW_ID)
const item = reviewItems.length === 1 ? reviewItems[0] : undefined
if (item?.selected.length !== 1 || item.selected[0] !== APPROVE_LABEL || item.custom !== undefined) {
  const feedback = item?.custom ?? ''
  throw new Error(feedback === ''
    ? 'The user chose to keep planning; revise the plan and present it again.'
    : `The user chose to keep planning; their feedback: ${feedback}`)
}
```
So a **port must not add a custom-answer field** to the plan-review card: an extra `custom` key would
register as a decline.

---

## 3. CROSS-CUTTING

### 3.1 Requests for a NON-active session [VERIFIED]

**Neither queued-and-shown-in-a-popup nor ignored: they are rendered only when you navigate there, and
advertised meanwhile as a sidebar status dot.**

1. **Published always.** `answerApproval`/`answerQuestion` run for every scoped request regardless of which
   session is on screen. The carrier is created and registered immediately —
   `ui-approval/src/client/index.ts:44-56`, `ui-user-questions/src/client/index.ts:63-68`.
2. **Stored per session, exactly one per session** — `ui-session/src/client/index.ts:366-386` (§1.5a).
3. **Rendered only for the current session** — `ConversationContent.tsx:114-115`.
4. **Advertised in the sidebar** as a `warning` status dot with a screen-reader label —
   `Rows.tsx:246-261`, `tests/rows.client.spec.tsx:514-544` (§1.5b).
5. **Nothing modal, nothing cross-session, nothing global.**

**Precedence when a session somehow has several pending interactions.** Domains declare a numeric
precedence; **higher wins**; ties go to the later-registered/earlier-scanned entry
(`>=` in `publishPendingInteractions` at `:375`):
```ts
if (previous === undefined || precedence >= previous.precedence) {
  next.set(interaction.sessionId, { interaction, precedence })
}
```
Registered precedences:
- Approvals: **0** — `ui-approval/src/client/index.ts:77-79`:
  ```ts
  const registerPendingInteraction = ctx.uiSession.registerPendingInteraction<PendingApproval>(
    () => 0,
  )
  ```
- Questions: **1**, plan-review: **2** — `ui-user-questions/src/client/index.ts:91-93`:
  ```ts
  const registerPendingInteraction = ctx.uiSession.registerPendingInteraction<PendingQuestion>(
    pending => pending.kind === 'plan-review' ? 2 : 1,
  )
  ```

So **plan-review (2) > question (1) > approval (0)**. Pinned by
`packages/client/ui-session/tests/ui-session.client.spec.ts:423-470`:
```tsx
it('publishes the highest-precedence exact object and removes each source independently', async () => {
  …
  const approval = { key: 'approval:1', kind: 'approval', sessionId: id }
  const duplicate = { key: 'approval:2', kind: 'approval', sessionId: id }
  const question = { key: 'question:1', kind: 'question', sessionId: id }
  const plan = { key: 'question:2', kind: 'plan-review', sessionId: id }
  const background = { key: 'background:1', kind: 'background', sessionId: id }
  const delegate = (): Promise<void> => Promise.resolve()
  const removeApproval = registerApproval(approval, delegate)
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(approval)
  const removeDuplicate = registerApproval(duplicate, delegate)
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(duplicate)
  const removeQuestion = registerQuestion(question, delegate)
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(question)
  const removePlan = registerQuestion(plan, delegate)
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(plan)
  const removeBackground = registerBackground(background, delegate)
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(plan)

  removeBackground()
  removeQuestion()
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(plan)
  removePlan()
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(duplicate)   // ← recomputed, not lost
  removeDuplicate()
  expect(service.pendingInteractions.getSnapshot().get(id)).toBe(approval)
  removeApproval()
  removeApproval()
  expect(service.pendingInteractions.getSnapshot().has(id)).toBe(false)
```
**Key insight: the loser is NOT discarded** — it stays in its domain and re-appears when the winner is
removed. So a port must hold a per-session *list* internally and *elect* the top one for display, even
though the display slot holds one.

README corroboration — `packages/client/ui-user-questions/README.md:93`:
> - **One request owns the composer at a time** — later pending requests remain in the session snapshot and become visible after the earlier request resolves.

**Related: chain priority.** `conversation.composer` entries declare `priority` (ascending = tried first) —
`packages/client/ui-slots/src/index.ts:259-270`. Registered values:
- Approval entry: `priority: 1` — `ui-approval/src/client/index.ts:80-89`:
  ```ts
  ctx.slots.inject('conversation.composer', () => ctx.slots.register({
    name: 'conversation.composer',
    priority: 1,
    select: ({ pendingInteraction }: ComposerChainProps): PendingApproval | null =>
      pendingInteraction instanceof PendingApproval ? pendingInteraction : null,
    locale: NS,
    children: {
      'conversation.approval.detail': { kind: 'single', scope: 'session' },
    },
  }, ApprovalPanel))
  ```
- Question entry: **no `priority`** → default `0` — `ui-user-questions/src/client/index.ts:94-103`:
  ```ts
  ctx.slots.inject('conversation.composer', () => ctx.slots.register(
    {
      name: 'conversation.composer',
      select: ({ pendingInteraction }: ComposerChainProps): PendingQuestion | null =>
        pendingInteraction instanceof PendingQuestion ? pendingInteraction : null,
      locale: NS,
      store: questionDraftStore,
    },
    QuestionComposer,
  ))
  ```
  Because the two selectors test `instanceof` on mutually exclusive classes, chain order is moot in practice
  — but a port should replicate the select-narrowing, not the priority ordering.

**Drafts are per-session and survive session switches** — `ui-user-questions/src/client/draft-store.ts:42-56`:
```ts
export function createQuestionDraftStore(): EngineStoreHandle<QuestionDraftState, QuestionDraftActions> {
  return defineStore({
    init: (): QuestionDraftState => ({ progress: emptyProgress() }),
    actions: {
      replace: (draft, requestKey, progress) => {
        draft.requestKey = requestKey
        draft.progress = progress
      },
      clear: (draft, requestKey) => {
        if (draft.requestKey !== requestKey) return
        delete draft.requestKey
        draft.progress = emptyProgress()
      },
    },
  })
}
```
Scope is per-Session (`ui-user-questions/src/client/index.ts:90`; `create(SID)` in tests). `clear` is a
no-op for a non-matching key — a late clear from an obsolete request cannot wipe the live one. Test —
`tests/question-draft-store.client.spec.ts:11-35`:
```ts
it('keeps one request progress and ignores cleanup from an obsolete request', () => {
  const store = createQuestionDraftStore().create('session-one')
  store.actions.replace('question:one', FIRST)
  expect(store.getSnapshot()).toEqual({ requestKey: 'question:one', progress: FIRST })

  store.actions.clear('question:older')
  expect(store.getSnapshot()).toEqual({ requestKey: 'question:one', progress: FIRST })

  store.actions.clear('question:one')
  expect(store.getSnapshot()).toEqual({ progress: { index: 0, drafts: [] } })
})
```
Restoration across a remount is asserted at `tests/user-questions-composer.client.spec.tsx:394-409`.

### 3.2 Deduplication and ordering [VERIFIED]

**Deduplication: only by key-collision rejection — NOT by content.**

`PendingInteractionDomain.publish` (`ui-session/src/client/index.ts:81-94`):
```ts
publish(interaction: T, delegate: () => Promise<void>): () => void {
  if (this.values.has(interaction.key)) {
    throw new Error(`ui-session: duplicate pending interaction key '${interaction.key}'`)
  }
  this.values.set(interaction.key, { interaction, delegate })
  this.changed()
  let active = true
  return () => {
    if (!active) return
    active = false
    if (!this.values.delete(interaction.key)) return
    this.changed()
  }
}
```
Test — `tests/ui-session.client.spec.ts:472-483`:
```tsx
it('rejects duplicate keys and contains a failing aggregate subscriber', () => {
  …
  expect(() => { registerPendingInteraction(interaction, delegate) })
    .toThrow("ui-session: duplicate pending interaction key 'question:1'")
```

Keys are **globally incrementing counters, unique per client process, never reused**:
- `contract/slots.ts:66,96-97` — `let nextApprovalKey = 0` … `this.key = \`approval:${String(nextApprovalKey)}\``
- `contract/slots.ts:98,136-137` — `let nextQuestionKey = 0` … `this.key = \`question:${String(nextQuestionKey)}\``
- Asserted at `tests/user-questions-composer.client.spec.tsx:435` — `expect(question.key).toMatch(/^question:\d+$/)`

**Consequence:** two *identical* requests arriving are two distinct carriers with distinct keys and are
**both** published — no content-level dedup. They merely compete under the precedence rule (§3.1), and the
loser surfaces after the winner resolves.

**Ordering on the wire.** Requests carrying the `'waterfall'` frame are delivered one at a time per
client, and each delivery is awaited as a task — so ordering is preserved by arrival:
`packages/api/gateway/src/client/remote-events.ts:154-166`:
```ts
const controller = new AbortController()
active.set(frame.eventId, controller)
const deliverySignal = AbortSignal.any([generationSignal, controller.signal])
const task = this.answer(frame, clientId, deliverySignal)
  .catch((error: unknown) => {
    if (!deliverySignal.aborted) failed.abort(error)
  })
  .finally(() => {
    active.delete(frame.eventId)
    tasks.delete(task)
  })
tasks.add(task)
```
Host side (`packages/api/gateway/src/index.ts:466-467`) mints a fresh UUID per request and guards collisions:
```ts
let id = randomUUID() as RemoteEventId
while (this.pendingRemoteEvents.has(id)) id = randomUUID() as RemoteEventId
```
Multiple clients may be offered the same request — `deliverRemoteEvent` broadcasts to every client
(`index.ts:510, 516-520`):
```ts
private deliverRemoteEvent(pending: PendingRemoteEvent, client: RemoteEventClient): void {
  pending.deliveries.add(client)
  client.deliveries.set(pending.id, pending)
  client.queue.push(pending.frame)
}
```
**First `{kind:'result'}` wins; the rest are idempotent no-ops** — `index.ts:522-541`:
```ts
private receiveRemoteEventResult(client, result): void {
  const pending = this.pendingRemoteEvents.get(result.eventId)
  // Settlement and Client replacement may race the result request. Results
  // from a completed event or a superseded delivery are idempotent no-ops.
  if (pending === undefined || !pending.deliveries.has(client)) return
  this.removeRemoteEventDelivery(pending, client)
  if (result.outcome.kind === 'result') {
    this.settleRemoteEvent(pending, { kind: 'result', value: result.outcome.value })
  } else if (result.outcome.kind === 'rejected') {
    this.cancelRemoteEvent(pending, restoreRemoteEventRejection(result.outcome.error))
  } else if (pending.deliveries.size === 0) {
    this.settleRemoteEvent(pending, { kind: 'next' })
  }
}
```
**Note the `next` semantics: it only settles when ALL deliveries have declined** (`pending.deliveries.size === 0`).
A `next` from one client while another is still deciding is a no-op.

**Answer-array ordering is by request order**, from `questions.map((item, itemIndex) => …)`
(`QuestionComposer.tsx:213`).

### 3.3 Connection drop and reconnect [VERIFIED — pending requests are DROPPED, not resumed]

**A pending approval or question does NOT survive a connection loss. It is cancelled/rejected, and the
model sees a failure.**

The chain, step by step:

1. **Generation ends → every active delivery is aborted** —
   `packages/api/gateway/src/client/remote-events.ts:171-176`:
   ```ts
   } finally {
     for (const controller of active.values()) {
       controller.abort(new Error('client api: Remote event generation ended'))
     }
     await Promise.allSettled(tasks)
   }
   ```
2. **Scope teardown → plugin teardown → delegate.** The `uiSession.registerPendingInteraction` effect
   disposer runs `domain.release()` and awaits each delegate (`ui-session/src/client/index.ts:314-320`).
   That delegate calls `pending.delegate()` → the listener returns `next()` (`ui-approval/src/client/index.ts:53-56`).
3. **Host side: the Agent Context release also cancels** — `packages/api/gateway/src/index.ts:470-479`
   and `closeRemoteEvents` at `:578-583`:
   ```ts
   private closeRemoteEvents(reason: unknown): void {
     for (const pending of [...this.pendingRemoteEvents.values()]) {
       this.cancelRemoteEvent(pending, reason)
     }
     for (const client of [...this.remoteEventClients.values()]) client.queue.end()
   }
   ```
   called from `:249` and `:260` on connection loss.
4. **The Host waterfall then falls through.** `packages/api/remotes/src/index.ts:147-156` — a `next` outcome
   runs the next listener; if none claims it, the terminal handler decides:
   ```ts
   resolve: (outcome: TypertRemoteEventOutcome) => {
     if (outcome.kind === 'result') {
       settled.resolve(outcome.value)
       return
     }
     void Promise.resolve().then(next).then(settled.resolve, settled.reject)
   },
   reject: settled.reject,
   ```
   - **Approvals** terminate at the fail-closed `'unavailable'` —
     `packages/interaction/user-approval/src/index.ts:273-277`:
     ```ts
     const answer: Promise<ApprovalOutcome> = Promise.resolve().then(
       () => this.ctx.waterfall(
         scopeTarget(req.agent, req.agent), 'approval/request', req,
         () => Promise.resolve<ApprovalOutcome>('unavailable'),
       ),
     )
     ```
     ⇒ model sees `tool "X" requires approval, but no approval channel is available`.
   - **Questions** terminate at a rejection —
     `packages/interaction/user-questions/src/index.ts:130-133`:
     ```ts
     const noAnswerer = () => Promise.reject(new UserQuestionError(
       'no user-questions answerer accepted the request',
       'NO_PROVIDER',
     ))
     ```
     ⇒ model sees a `NO_PROVIDER` error.

**Verification at the client-tier with a passing test** —
`packages/api/gateway/tests/gateway-stream.host.spec.ts:536`:
```ts
await expect(stale.outcome).resolves.toEqual({ kind: 'next' })
```
and `:519-536` covers the stale-delivery case. Also
`packages/api/gateway/tests/remote-events.host.spec.ts:212`:
```ts
delegatedDispatch.resolve({ kind: 'next' })
```

**There is no persistence, no replay, no resume.** The `pendingRemoteEvents` map lives in memory on the
Host (`index.ts:185`) and is torn down on generation loss. Nothing writes a pending approval to the
session log — only `approval/asked` + `approval/decided` are durable, and `approval/decided` is appended
only when the outcome IS known (`packages/interaction/user-approval/src/index.ts:208-227`).

⚠️ **Asymmetry worth porting deliberately:** durable audit ≠ resumable UI. A port that wants
"reconnect and still see the prompt" would need a mechanism the reference does **not** have.

**[INFERRED]** There is one nuance: because the delegate goes through `next()` rather than a rejection,
in a *multi-answerer* composition (e.g. a TUI answerer also composed) the request could be picked up by
the other answerer rather than failing. In the pure web-client composition the web answerer is the only
one, so it fails closed as described.

---

## 4. Flutter porting checklist (distilled) [INFERRED from verified facts]

**Approval card**
- [ ] Render as a bottom-of-conversation card replacing the input bar; max width = chat content width; 20px radius; warning border; level-2 shadow.
- [ ] Four bands: warning strip (`Waiting for approval` + 8px dot) → headline (`reason`, else `Tool {name} requests privileged execution`) → optional monospace detail (shell `command` only) → right-aligned `[Reject (outline, danger hover)] [Allow once (primary)]`.
- [ ] Exactly two buttons; no ✕; no Esc; no timeout.
- [ ] Send `outcome.value = 'allowed-once'` or `'rejected'` — bare hyphenated strings.
- [ ] On click disable both; on send failure re-enable both silently (no error text).
- [ ] Header is a scroll region capped at the composer text height, `role=group`, labelled `Approval details`.
- [ ] Handle incoming `rejected` (Host abort) and `next` (delegate) as non-user outcomes.
- [ ] Handle `'cancelled'` and `'unavailable'` only as *incoming Host states*, never as buttons.
- [ ] No sound, no push notification.

**Question card**
- [ ] Paginated one-question-at-a-time with `n / N` pager; header/footer fixed, detail+options scroll.
- [ ] Header: optional eyebrow (`header`) + `<h2>` (`question`) + minimize toggle + ✕ (dismiss-all).
- [ ] Options: single-select → ordinal number + `radio`; multi-select → checkbox + `checkbox`; single-select auto-advances.
- [ ] Freeform: inline "Other" row when options exist (checkbox marker for multi, pencil for single); full-block textarea when no options; autofocus once per index.
- [ ] Enter = continue/submit; Shift+Enter = newline; ignore IME-composition Enter (`isComposing` / `keyCode 229`).
- [ ] Single-select custom text clears the selection; multi-select keeps it.
- [ ] Strip `(Recommended)`/`（推荐）` case-insensitively for display + show a badge; **send the raw label**.
- [ ] Footer: `‹ n/N ›` pager, `role=status` error line, `Skip` (outline), primary button (`Next` / `Submit` / `Submitting…`), disabled unless the current question is answered.
- [ ] Validate: current question answered to advance; ALL questions answered-or-skipped to submit; jump to first offender + show `Please complete this question first.` / `Please select an option or enter a custom answer.`
- [ ] Skip clears that question's draft, emits `{id, selected: []}`, auto-advances, and auto-submits when last.
- [ ] Encode: skipped → `{id, selected: []}` (no `custom`); single+custom → `{id, selected: [], custom}`; multi → `{id, selected, custom?}`; trim `custom`; omit the key when empty.
- [ ] ✕ → reject with `UserQuestionError` / `ASK_CANCELLED` / `the user cancelled ask_user_question`; show the error and re-arm on failure.
- [ ] Plan-review variant: strip `Plan review` + markdown body + `[Chat about it (ghost)] [Refuse (outline)] [Approve (primary)]`; the asker's label rides the tooltip; answer sends the asker's label; all three lock together.

**Cross-cutting**
- [ ] Hold a per-session LIST of pending interactions; display the highest precedence (plan-review 2 > question 1 > approval 0); the loser re-appears when the winner clears.
- [ ] Show non-active sessions' pending state as a **warning status dot** on the sidebar row (outranking `running`), with labels `Waiting for approval` / `Plan awaiting review` / `Waiting for answer`; the row click navigates.
- [ ] No content-level dedup; keys are unique counters; duplicate keys are a programming error.
- [ ] On disconnect, pending requests are cancelled → the Host answerer falls through to `next` → approvals resolve `'unavailable'`, questions reject `NO_PROVIDER`. Do not attempt to resume unless deliberately extending the reference.
