# 会话状态域 V4（对标 dsh-go Runtime Supervisor 架构）

> 本文记录「对话状态」这套分层为什么这样设计。改动前先读它；
> 要改原则，先改这份文档并说明理由。
> 上游参照：dsh-go V4（`docs/architecture/dsh-go-v4-final-architecture.md`、
> `dsh-go-v4-hardened-runtime-architecture.md`，本地克隆于 `D:\Hermes_workspace\dsh-go`）。

## 一、dsh-go V4 → 会话域映射

| dsh-go V4 概念 | 会话域落地 | 代码 |
|---|---|---|
| Runtime Supervisor（唯一 mutation 权威） | 轮次状态唯一写入口 | `lib/services/turn_supervisor.dart` |
| Runtime State V4（极简状态 + generation） | `TurnState {generation, phase, streaming, activeTool, turnClosed, updatedAt}` | `lib/models/turn_state.dart` |
| generation CAS（存储侧最后安全闸） | `SessionState.applyTurnState`：generation 不大于当前直接丢弃 | `lib/services/session_state.dart` |
| Transaction Engine（一次失败不产生半状态） | 一个命令一次 `applyTurnState`，UI 不见中间帧（旧实现 turn/end 连广播 6 次） | supervisor `_commit` |
| Trust + Policy（闸门/策略唯一实现） | `turnClosed` 迟到事件闸门只在 supervisor 的 `authorityRunning` 里 | `turn_supervisor.dart` |
| Activation Manager / LKG | turn/end 队列非空 → `queued` 相位（busy 延续）；权威 `running:false` 永远可落 idle（自愈通道） | `turnEnd` / `authorityRunning` |
| Audit（append-only） | 审计环（最近 50 条，迁移与拒绝都留痕） | `TurnSupervisor.auditLog` |
| Runtime Adapter ABI | `AgentBackend`（DshBackend / OpenCodeBackend 同级实现） | 既有，不动 |
| Architecture Conformance Gate | 源码扫描门禁：写入口唯一性、screens 禁直连后端 | `test/architecture_gate_test.dart` |

## 二、状态机

```text
                 beginLocalSend（乐观，无条件）
        ┌──────────────────────────────────────► sending ─┐
        │                                                 │ userMessageArrived（回显）
      idle ◄── failLocalSend（仅 sending 可回滚）           ▼
        ▲                                              running ◄── turnStart / toolCall
        │                                                │  ▲       / assistantStreamStart
        │ authorityRunning(false)（永远接受，自愈）         │  │ streamTick（!turnClosed）
        │ queueDrained（队列空且新轮未到）                  ▼  │
        └──────────────────────────── queued ◄─ turnEnd(队列非空)
                                          │
                            turnEnd(队列空) → idle
```

- `idle`：空闲。
- `sending`：本地乐观发送已发生、权威确认未到（「点了发送却显示假空闲」的空窗）。
- `queued`：本轮已收尾但 Host 队列还有本会话的排队/插话 —— **busy 的延续**，
  停止按钮不得在 turn/end→turn/start 间隙闪断成发送。
- `running`：权威 turn 激活中。`streaming`（打字机态）与 `activeTool`（状态栏工具条）
  是 running 的修饰位，随命令原子同帧变更。

`agentRunning`（UI 兼容 getter）= `turn.busy` = phase ≠ idle。

## 三、闸门语义（唯一实现，勿在他处复制）

1. `running:true` 只在本轮未收尾（`!turnClosed`）时接受 —— 重连重放 / 迟到的
   状态推送不是新一轮；真正的新一轮必先发 `turn/start`（重新武装）或
   durable 用户消息（`userMessageArrived` 重新武装）。
2. `running:false` 永远接受，并顺带收掉工具条与打字机态 —— 这是失败路径
   事件全丢时的权威自愈通道。
3. 乐观发送（`beginLocalSend`）无条件置 busy —— 方向安全，权威随时可纠正。
4. stale-busy 自愈「只清不设」：消息流证据判定在调用方（`isSessionActuallyIdle`），
   supervisor 只负责落 idle。

## 四、队列域（任务运行中继续输入）

- 发送始终走 `session/prompt` `mode:'queue'`：运行中 Host 自动排队/插话，
  空闲时立即开跑 —— 客户端不区分，行为交给 Host。
- 队列快照来源：`session/control` 的 `queue` 帧（`{type, sessionId, items}`）与
  `control/baseline`（`{queues: {sessionId: [...]}}`），条目形状见
  `docs/MUX_PROTOCOL.md:272`。
- 消费链：`mux_frame_events`（带 sessionId）→ `event_queue.dart`：
  ① rpcId 命中 → 乐观气泡转确认态（Host 受理的可视反馈）；
  ② 队列视图按会话隔离整体替换（`SessionStateQueue.replaceQueue`）；
  ③ 相位联动（先落视图再判相位，顺序不可换）。
- 横幅计数只算 `queued` + `steering`；`context` 是运行时上下文注入，不是用户排队。
- opencode 无队列帧：队列视图恒空、横幅不出现，状态机自动工作 ——
  队列可视是 DSH 权威能力，状态机是后端无关的。

## 五、写入口纪律（门禁锁定）

| 写入 | 唯一入口 | 门禁 |
|---|---|---|
| 轮次状态 | `TurnSupervisor`（经 `applyTurnState`） | `architecture_gate_test.dart` |
| 队列视图 | `event_queue.dart` → `replaceQueue` | 同上 |
| 乐观气泡生命周期 | `event_message_reconcile.dart` | 既有约定 |
| 页面 → 后端 | 只经 `ChatController` 门面（配对引导与 `backend_ops` 豁免） | 同上 |

旧 setter（`setAgentRunning` / `setAssistantStreaming` / `setActiveTool`）已删除。
发现编译错误指向它们 = 有代码在绕层写状态，改走 supervisor 命令，不要恢复 setter。
