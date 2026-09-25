# DSH Remote mux 协议 — 权威规格

> 本文由 DSH 源码与测试逐条核对得出（**非推断**）。平板端所有 mux 相关代码以本文为准。
> 若与旧文档 `docs/API_DOC.md` 冲突，以本文为准 —— 旧文档 §3.2 曾把 `waterfall` 帧写成另一种形状，是错的。

## 证据来源

| 文件 | 用途 |
|---|---|
| `packages/api/gateway/src/stream-protocol.ts` | 帧类型定义、`$events/result` 解析 |
| `packages/api/gateway/tests/gateway-stream.host.spec.ts` | **真实 socket / HTTP 报文**（最佳依据） |
| `packages/client/connection/src/client/rpc.ts` | 客户端 RPC 信封与响应校验 |
| `packages/api/gateway/src/client/remote-events.ts` | Host 侧应答与 `agentId` 解析 |
| `packages/api/session-controller/src/types.ts` | follow / control 帧结构 |
| `packages/api/session-controller/tests/remote/session.client.ts` | follow 开窗 payload |
| `packages/api/session-controller/src/index.ts` | `follow(request, signal)` 形参名 = 线上字段名 |
| `packages/api/session-controller/src/client/transport.ts` | 生成客户端实际发出的 args |
| `apps/web/tests/smoke-real.e2e.ts` | **真实端到端**的 open / HTTP 报文 |
| `fs/tool-fs/src/diff.ts` | `FileDiff` / `FsDiffMeta` 形状 |

### 参数命名规则（本轮踩坑最多的一条）

Remote 方法的业务参数若**只有一个对象**，线上字段名**就是该形参名**：
- `follow(request: SessionFollowRequest, signal)` → `args: { request: {...} }`
- `page(request..., throughSeq, signal)` → `args: { request: {...}, throughSeq: n }`
- `control(signal)` / `follow(signal)`（workspace）/ `$events` → `args: {}`

多一层或少一层都会让 Host 参数解析失败；`session/follow` 少写这层时
**既拿不到历史也没有流式**，且表面上看不出原因。

---

## 1. WebSocket 与逻辑流

- 路径：`/api/remote.mux`
- 认证：`Cookie: dsh-auth-xxx=...`（WebSocket upgrade header）
- Ping：20s

### 客户端 → 服务端（仅两种消息）

```json
{ "type": "open", "streamId": "...", "endpoint": "...", "payload": { "args": {} } }
{ "type": "cancel", "streamId": "..." }
```

### 服务端 → 客户端（外层帧仅三种）

```json
{ "type": "item",  "streamId": "...", "value": { ... } }
{ "type": "error", "streamId": "...", "error": { "code": "...", "message": "...", "details": {} } }
{ "type": "end",   "streamId": "..." }
```

> **关键**：业务帧的 `type` 在 `value.type`，且每种流的业务帧都是**扁平**的。
> 不存在 `{ event: { type, data } }` 这种嵌套 —— 早期实现按嵌套解析，导致审批/提问永不触发。

### 四条逻辑流

| streamId | endpoint | 用途 |
|---|---|---|
| `evt` | `$events` | 审批 / 提问 waterfall 与广播 |
| `fol` | `session/follow` | 会话历史快照 + journal 事件 + 打字机帧 |
| `wfo` | `workspace/follow` | 归档会话列表 |
| `ctl` | `session/control` | 全局队列 / 后台任务 / 投影 |

---

## 2. `$events` 流（审批 / 提问）

Open：

```json
{ "type": "open", "streamId": "evt", "endpoint": "$events", "payload": { "args": {} } }
```

`value.type` 取值：

| type | 结构 | 说明 |
|---|---|---|
| `ready` | `{ type, clientId, host: { home } }` | **clientId 与物理 socket 绑定，重连后必须重新获取** |
| `waterfall` | `{ type, event, eventId, agentId, request }` | 待应答请求 |
| `cancel` | `{ type, eventId }` | 已被别处应答，应清卡 |
| `emit` | `{ type, event, args }` | 广播，如 `api-session/status` |

### waterfall

- **`agentId` 就是 sessionId**（在 `ui-agent-preset` / `ui-reference` 中类型标注为 `SessionId`）。
  用它才能正确区分「别的会话发来的审批」。
- `event` 为 `'approval/request'` 或 `'user-questions/request'`
- `request` 是该事件的参数对象：审批含 `toolName` / `reason` / `callId`；
  提问含 `questions[]`

### emit

```json
{ "type": "emit", "event": "api-session/status", "args": ["<sessionId>", true] }
```

`args` 是**数组**（Cordis 监听器的位置参数），不是对象。
`api-session/*` 是 Host 允许广播的白名单：

| event | args |
|---|---|
| `api-session/status` | `[sessionId, running]` |
| `api-session/error` | `[sessionId, message]` |
| `api-session/activity` | `[sessionId, updatedAt]` |
| `api-session/added` | `[SessionSummary]` |
| `api-session/removed` | `[sessionId]` |

> ⚠️ **`emit` 只出现在 `$events` 流，`session/follow` 上没有这个帧。**
> 会话运行状态的唯一实时来源就是这里的 `api-session/status`；
> 不存在 `session/status` 这个 HTTP 端点，`session/control` 也没有同名帧。

### cancel

```json
{ "type": "cancel", "eventId": "<eventId>" }
```

Host 在待应答 waterfall 生命周期结束时下发（别处已应答 / 会话销毁）。
只需按 `eventId` 清卡。

---

## 3. `$events/result` HTTP RPC

`POST /api/$events/result`，`Content-Type: application/json`，带 cookie。

### 请求

```json
{
  "type": "client-request",
  "rpcId": "<uuid>",
  "method": "$events/result",
  "payload": {
    "args": {
      "clientId": "...",
      "eventId": "...",
      "outcome": { "kind": "result", "value": "allowed-once" }
    }
  }
}
```

### outcome 三种形态

| 形态 | 含义 |
|---|---|
| `{ "kind": "result", "value": <any> }` | 已作答 |
| `{ "kind": "next" }` | 本客户端不处理，交给下一个监听者 |
| `{ "kind": "rejected", "error": { name, message, code?, details? } }` | 监听者抛错 |

审批取值：允许一次 = `'allowed-once'`；拒绝 = `'rejected'`。
提问取值：`{ "answers": [ { "id": "...", "selected": [...], "custom": "..." } ] }`。

### 响应

```json
{ "type": "server-response", "rpcId": "<与请求相同>", "result": { "ok": true } }
```

失败：`{ "result": { "ok": false, "error": { "message": "..." } } }`

> **必须校验 `rpcId` 回显一致**，并检查 `result.ok === true` 才算成功。

---

## 4. `session/follow` 流

Open：

```json
{
  "type": "open", "streamId": "fol", "endpoint": "session/follow",
  "payload": { "args": {
    "request": {
      "address": { "kind": "session", "sessionId": "..." },
      "assistantStream": true,
      "maxMessages": 60
    }
  } }
}
```

> ⚠️ **必须有 `request` 包装层。** Host 侧签名是
> `follow(request: SessionFollowRequest, signal)`；生成客户端的规则是
> 「单对象首参 → 线上字段名即参数名」，所以 `args` 里是 `{request: {...}}`。
> 漏掉这层，Host 参数解析失败会直接拒流 —— 表现为**既没有历史也没有流式**。
>
> 对照：`session/control`、`workspace/follow` 的业务参数**只有 `signal`**，
> 所以它们就是 `{"args":{}}`；`$events` 同样（args 必须为空，否则
> `gateway/arguments-invalid`）。
>
> `address` 也可以是 subagent：`{ kind:'subagent', parentSessionId, childSessionId, mode }`。

### 下行帧（`value.type`）

| type | 结构 |
|---|---|
| `snapshot` | `{ type, header, cursor, records, hasMore, projections, assistantStream? }` |
| `event` | `{ type, event: { type, seq, time, data } }` |
| `assistant-stream` | `{ type, frame }` |

`records` 的元素与实时 `event` 帧**同构**，所以解析逻辑必须共用一条路径。

### snapshot 的价值（易被忽略）

- `header`：`{ id, createdAt, cwd, parentSession?, isSeeded, origin?, agentPreset? }`
- `projections`：会话投影（**标题等实时元数据来源**）
- `hasMore`：是否还有更早历史（配合 `session/page` 翻页）
- `assistantStream`：**重连时正在进行的助手流基线**，
  `activeAttempt.stream` 是已累积的紧凑片段 —— 不读它，断线重连会丢失正在输出的文本

### `assistant-stream` 的 frame

| frame.type | 说明 |
|---|---|
| `start` | 一次尝试开始（含 attemptId/revision/turn/step） |
| `chunk` | `{ attemptId, revision, index, time, chunk }`，`chunk` 形如 `{ type:'text-delta', text }` |
| `end` | `{ attemptId, revision, index, outcome }`，outcome 为 `{kind:'committed', eventType, seq}` 或 `{kind:'abandoned'}` |

`index` 是**稠密序号**，可用于丢弃乱序/重复的 chunk。

### journal 事件（`event.type`）

| type | data |
|---|---|
| `turn/start` | `{ turn }` |
| `turn/end` | `{ turn, reason }`，`reason.kind === 'error'` 时含 `error.message` |
| `step/start` / `step/end` | `{ turn, step }` |
| `user/message` | `{ id, role:'user', content, source }`，`source.rpcId` 用于回显对账 |
| `assistant/message` | `{ turn, step, message:{content}, stream, usage?, interrupted? }` |
| `assistant/attempt` | `{ turn, step, stream }` |
| `tool/call` | `{ turn, step, callId, name, arguments }` |
| `tool/result` | `{ turn, step, message, error?, meta? }` |
| `approval/asked` / `approval/decided` | 审批的持久审计记录 |

> ⚠️ **`assistant/chunk` 不是现行事件。** 它只存在于 format ≤ v2 的旧产物里，
> v2→v3 迁移会显式删除它。实时增量只走 `assistant-stream` 帧；
> 持久化形态是 `assistant/message.data.stream`。

> ⚠️ `tool/call.data.arguments` 是**未解析的 JSON 字符串**，需要自行 decode。

### diff 的真实来源（重要）

**线上不存在 `view` 字段，也没有 `tool/view` 事件。** diff 在：

```
tool/result.data.meta.diffs = [ { path, oldText: string|null, newText: string } ]
```

`oldText === null` 表示整文件新建。调用参数里的 diff 属于「意图」，
需要从 `tool/call.data.arguments`（JSON 字符串）自行推导。

---

## 5. `session/control` 流

Open：`payload: { "args": {} }`

| type | 结构 |
|---|---|
| `baseline` | `{ type, value: { queues, jobs, projections } }` |
| `queue` | `{ type, sessionId, items }` |
| `jobs` | `{ type, sessionId, jobs }` |
| `projection` | `{ type, sessionId, key, value, seq }` |

> 帧名就是 `baseline` / `queue` / `jobs` / `projection`。
> **不存在** `control/baseline`、`queue/update`、`projection/change`（早期实现自造的名称）。

`SessionQueuedItem`：`{ id, placement:'queued'|'steering'|'context', rpcId?, message:{ id, content } }`
`SessionJob`：`{ id, kind, label, status:'running'|'stopping'|'completed'|'killed'|'failed', detail?, startedAt, finishedAt? }`

---

## 6. `workspace/follow` 流

Open：`payload: { "args": {} }`

| type | 结构 |
|---|---|
| `baseline` | `{ type, value: { items, archivedSessionIds } }` |
| `archived` | `{ type, archivedSessionIds }` |

注意二者取 `archivedSessionIds` 的位置不同：baseline 在 `value` 里，archived 在顶层。

---

## 7. HTTP 端点（同一 client-request 信封）

| 端点 | 请求 args | 响应 |
|---|---|---|
| `session/list` | `{}` | `{ items: [SessionSummary] }` |
| `session/create` | `{ request: { cwd?, workspaceId?, sessionId?, agentPreset? } }` | `{ sessionId }` |
| `session/prompt` | `{ request: { requestId, sessionId, mode, content } }` | `{ accepted: true }` |
| `session/cancel` | `{ request: { sessionId } }` | `{ accepted: true }` |
| `session/page` | `{ request: { address, throughSeq, beforeSeq?, maxMessages? } }` | `{ records, hasMore }` |
| `session/rename` | `{ request: { sessionId, title } }` | `{ title, seq }` |
| `session/updateQueue` | `{ request: { sessionId, itemId, action } }` | `{ accepted: true }` |
| `subagents/list` | — | `{ entries, parentAvailable }` |

> **参数命名规则**：Remote 方法的业务参数若只有一个对象，线上字段名
> **就是该形参名**（通常 `request`）；零业务参数（只有 `signal`）时用 `{}`。
> 所有端点都是 `POST /api/<namespace>/<method>`，且**成功与逻辑失败都返回
> HTTP 200** —— 必须检查 `result.ok`，不能只看状态码。

> ⚠️ **不存在 `session/status` 端点**，也不存在 `workspace/list` 端点。
> 前者由 `session/list` 的 `running` 字段 + `api-session/status` emit 提供；
> 后者只能从 `workspace/follow` 的 baseline 读。

---

## 8. 实现红线（踩过的坑）

1. `clientId` 必须从 `ready` 帧取；**断开即作废**，重连后重新取，否则应答全部失败。
2. 业务帧按 `value.type` 扁平解析，不要找 `value.event.type`。
3. `$events/result` 必须带完整 `client-request` 信封，`outcome` 必须带 `kind`。
4. 审批归属用 `waterfall.agentId`，不要用当前 mux 的会话 id。
5. `emit` 帧**只出现在 `$events` 流**，`args` 是数组。
6. snapshot 的 `assistantStream` 是重连不丢字的关键。
7. 请求/响应都要校验 `rpcId`；成功判据是 `result.ok === true`（没有 `value` 键）。
8. `session/follow` 的 args **必须**有 `request` 包装层。
9. diff 只在 `tool/result.data.meta.diffs`；**没有 `view` 字段**。
10. 发 `{type:'cancel'}` 后 Host **不会**再发 `end`/`error`，不要等。
