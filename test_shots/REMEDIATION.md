# DSH Tablet Client 整改方案

基于 `test_shots/FINAL_REPORT.md` 的实测，对照当前源码。按用户可感知的严重程度分三批，每项含根因、改法、验收。

## 第一批（P0，先做）

### 1. 停止必须真的停，失败必须说出来

**现状** `lib/services/chat_controller.dart` `cancel()`：

- `DshApi.cancelSession` 已经返回 `accepted`，调用方丢掉了。
- `finally` 里无条件 `agentRunning = false`。HTTP 失败、`accepted: false`、请求还在飞，按钮都会消失。
- `DshApi._rpc` 统一 `httpTimeout`（30s）。实测 App 的 cancel 要 15–30s 才返回，Python 同接口是毫秒级。按钮在这期间一直亮着，turn 自己跑完，reason 仍是 `completed`。

**改法**

1. `cancelSession` 增加独立超时（5s），不要走 30s 默认。
2. `cancel()` 只在 `accepted == true` 时进入「正在停止」。`accepted == false`、超时、非 200：保持 `agentRunning`，SnackBar `停止失败，Agent 仍在运行`。
3. 真正清掉停止按钮只靠 `onSessionStatus(running: false)` / `finishRunning()`，不要在 `finally` 里抢先清。
4. 停止进行中按钮改为「正在停止…」并禁用连点。

**验收**

- 长任务（例如 `Start-Sleep -Seconds 90`）点停止后，5s 内服务端 `turn/end.reason.kind == aborted`。
- 断网或 `accepted: false` 时按钮还在，并出现失败提示。

### 2. 用户气泡不能在出队时被删掉

**现状** `lib/services/chat_message_mixin.dart`

- `send()` 先插入乐观气泡，回声到达时 `onUserMessage` 用 `rpcId` / 60s 文本窗口去重，故意不插第二条。设计是乐观气泡留下来。
- `onQueueUpdate` 把「离开队列的文本」从 `messages` 里 `removeWhere(role == user)`。队列清空表示「已被 Agent 取走」，不是「用户没说过」。
- 结果：气泡被删，回声又被去重挡住，服务端有 `user/message`，界面没有。重连走 snapshot 才会回来。

**改法**

1. 删掉 `onQueueUpdate` 里对 `messages` 的 `removeWhere`。队列只更新 `queuedTexts`（排队标记），不改聊天记录。
2. 乐观气泡用 `rpcId` 做 id（`u-$rpcId`）。回声到达时如果 id 已在列表里，更新为服务端 seq，不要删。
3. 只有服务端明确取消排队、且从未变成 `user/message` 时，才移除「排队中」气泡。当前协议没有这个信号就不要删。

**验收**

- 连续发 3 条，turn 全部结束后 3 条用户气泡仍在。
- 重连前后条数一致。

## 第二批（P1）

### 3. 助手最终消息不要再追加一条

**现状** `onAssistantFinal`：

- 找到 `isStreaming` 就 `copyWith(content: text)`，但没有把 `isStreaming` 置 `false`。
- 找不到就 `messages.add` 一条新的。
- `onTurnEnd` / `finishRunning` 会先把流式气泡收尾（`isStreaming: false`）。若最终帧晚到，就会再追加一整段。实测同一条回复出现「半截 + 全文」，服务端只有一条 `assistant/message`。

**改法**

1. 替换流式气泡时同时 `isStreaming: false`。
2. 没有流式气泡时，若最后一条 assistant 内容是本次 `text` 的前缀或完全相同，就原地替换，不要 `add`。
3. 同一 turn 只保留一条 assistant 正文。工具状态条继续走 `activeTool`，不进消息列表。

**验收**

- 长回复结束后，列表里该轮只有一条 assistant，内容等于服务端 `assistant/message`。

### 4. 提问提交：失败要看得见，成功必须关

**现状** `submitQuestion` → `MuxStream.respondQuestion` → `POST /api/$events/result`，15s 超时，`ok != true` 就返回 false。Sheet 只有返回 true 才 `pop`。第一次实测 Host 已收下答案，Sheet 5s 后仍开着，提交按钮已恢复可点（请求已结束且被当成失败）。

**改法**

1. 失败 SnackBar 不要被 Dialog 挡住：用 root `ScaffoldMessenger`，或先保持 Sheet 并在 Sheet 内显示「未被接受，可重试」。
2. `onQuestionResolved` / `onTurnEnd` 继续负责关 Sheet（已有）。补一条：若 POST 返回 false，但 2s 内收到 resolved，视为成功，不要再报「未被接受」。
3. 打一条调试日志：`clientId`、`eventId`、HTTP status、`result.ok`。用同一次提问对照 Host 日志，确认是超时、clientId 错位，还是 envelope 解析。

**验收**

- 连续两次提问，提交后 1s 内 Sheet 关闭，Host `tool/result` 含所选答案。
- 故意用过期 eventId，Sheet 内出现可重试错误，不会无提示卡住。

### 5. 断连要看得见，发送失败要把字还回来

**现状** `ChatInputBar` 在 `!connected` 时直接 `enabled: false`，发送按钮 `onPressed: null`。没有横幅。`_send()` 先 `clear()` 再 `send()`，失败时输入丢失。键盘没打开时 BACK 会退出 Activity。

**改法**

1. 顶部细条：`连接中断，正在重连…` / `已停止自动重连`（看 `autoReconnect`）。
2. 断连时输入框保持可编辑，发送按钮点击后提示「未连接」，不要清空。
3. `send()` 抛错时把文本写回 controller（现在 clear 在 await 之前）。
4. 根路由 `PopScope`：对话页 BACK 先关抽屉 / 键盘，再 BACK 不直接 `finish`。回桌面只走 Home。

**验收**

- 拔网或等断连：能看到横幅，输入还在，点发送有提示。
- 恢复后横幅消失，原文本可发出。

### 6. 变更抽屉打得开

**现状** `chat_screen.dart` 用 `Builder` + `Scaffold.of(drawerContext).openEndDrawer()`。按钮 `enabled=true`，坐标点在按钮内，抽屉没出现。左侧会话抽屉用系统菜单按钮，是正常的。

**改法**

1. `ChatScreen` 持有 `GlobalKey<ScaffoldState>`，变更按钮直接 `key.currentState?.openEndDrawer()`。
2. `openEndDrawer` 返回前如果 state 为 null，SnackBar `无法打开变更`，不要静默。
3. 空列表明确写「本轮没有文件变更」，避免打开后看起来像没反应。

**验收**

- 点变更，右侧抽屉 300ms 内出现（有 diff 或空态文案）。

## 第三批（P2，随手带上）

### 7. 前台保活失败要提示

`_ForegroundServiceTile._toggle` 在 `startService` 抛错时不会 `setState`，开关保持关，也没有错误。实测点开关后 `dumpsys` 没有 ServiceRecord。

- `try/catch`，失败 SnackBar 写出异常（权限 / 通知 / 未 init）。
- 成功后再把 `_running` 设为 `FlutterForegroundTask.isRunningService` 的真实值，不要假定 `value` 已生效。

屏幕常亮已实测可切换，不用改逻辑。

### 8. 拆文件，顺手补无障碍

当前 `chat_screen.dart` 450 行、`settings_screen.dart` 428 行，都超过 400。

- 停止 / 发送 / 提问对话框留在 screen；AppBar、断连横幅拆到 `widgets/`。
- 设置里前台服务 tile 已是独立类，可挪到 `widgets/foreground_service_tile.dart`。
- `ChatInputBar` 的 `TextField` 加 `semanticsLabel: '输入消息'`（hint 目前不进无障碍树）。

### 9. 明确不做

- 审批卡片：本环境 `workspace-write` + `ask` 下，写工作区外被沙箱拒绝后走的是提问单，不是审批瀑布。卡片代码路径先只做审查，不阻塞这轮整改。
- 更新弹窗、扫码、暗色：这轮没测完，不进本方案。

## 建议落地顺序

| 顺序 | 项 | 主要文件 | 预估 |
|------|----|----------|------|
| 1 | 用户气泡 | `chat_message_mixin.dart` | 小 |
| 2 | 停止 | `dsh_api.dart`、`chat_controller.dart`、`chat_screen.dart` | 小 |
| 3 | 助手去重 | `chat_message_mixin.dart` | 小 |
| 4 | 断连横幅 + 发送回填 | `chat_screen.dart`、`chat_input_bar.dart` | 中 |
| 5 | 变更抽屉 | `chat_screen.dart` | 小 |
| 6 | 提问失败可见 | `question_sheet.dart`、`chat_screen.dart` | 小 |
| 7 | 前台保活错误 | `settings_screen.dart` | 小 |

1–3 可以一次改完再装一次 Debug APK。验收仍用现在的模拟器：发消息、点停止、对 `session/page` 的 `turn/end.reason`。

---

# 实施与验证结果

代码已全部落地，`flutter analyze --no-fatal-infos` 只剩 6 条既有 `activeColor` 弃用提示（0 error / 0 warning）。以下为逐项实测。

## 一个必须更正的前期结论

原报告写「停止 6/6 全部无效，服务端始终 `completed`」。**这个结论是错的**，验证阶段做了对照实验才定位清楚：

1. 把 `cancel()` / `cancelSession` 退回改动前的旧实现，重新编译安装，在**健康的模拟器**上重测 → `turn 13 aborted`。旧代码同样能停。
2. 那 6 次失败期间，模拟器 `system_server` 处于卡死状态，日志有 `BLOBSyncEngine: ... Application ANR likely to follow`，`/data/anr/` 在对应时段堆了 20+ 份 trace。点击事件根本没送达应用（`InputDispatcher: ... Waited 5044ms for KeyEvent ... not responding`）。

根因是**测试环境过载**，不是应用缺陷。当时主机可用内存只剩约 1.6G，而 AVD 原生面板是 2560x1600 纯软渲染（`hw.gpu.enabled = no`），qemu 占 4.1G。释放 Gradle daemon（1.4G）+ 把面板降到 1920x1200 + AVD 内存提到 2048M 后，模拟器稳定，同一操作立刻正常。

所以第 1 项的修复价值要重新表述：**不是「让停止从不能用变成能用」，而是「停止没生效时不再假装已生效」**——去掉 `finally` 里无条件的状态清理、尊重 `accepted`、独立 5s 超时、进行中显示进度并禁用连点。

## 验证结果

| 项 | 状态 | 实测证据 |
|----|------|----------|
| 1 停止 | 通过 | 正式版连测两次：`turn 12/13/14` 点停止后均为 `reason.kind == aborted`，按钮 4s 内消失 |
| 2 用户气泡 | 通过 | 排队场景：`sleep 60` 运行中发第二条，两条回合都结束后两条气泡都在；被 `aborted` 的轮次气泡同样保留 |
| 3 助手去重 | 通过 | 长回复结束后该轮只有一条 assistant，无「半截 + 全文」 |
| 4 提问失败可见 | 仅代码审查 | 未构造出失败场景（需过期 eventId），逻辑已按方案改为 Sheet 内联报错 |
| 5 断连横幅 + 发送回填 | 通过（含一处新修复） | 见下 |
| 6 变更抽屉 | 通过 | 点变更，右侧抽屉打开并显示「本会话暂无文件变更」 |
| 7 前台保活错误 | 仅代码审查 | 模拟器上未复现启动失败 |
| 8 拆文件 | 部分 | `chat_screen.dart` 492 行仍超 400，未拆 |

## 验证中发现并修复的新问题

**断连检测缺失**（比原方案第 5 项更底层）。原方案只做横幅，但 `IOWebSocketChannel.connect` 没有设 `pingInterval`，网络硬断时 WebSocket 不会报错，`connected` 一直是 `true`，`onDisconnected` 永不触发——**横幅代码是对的，只是永远等不到触发条件**。

实测：`svc wifi disable` 后 50s 无横幅。加 `pingInterval: 20s` 后，横幅在 **+30s** 出现（一次丢 pong），恢复网络后 10s 内自动重连、横幅消失、消息可正常发出。

修改：`lib/services/mux_stream.dart`。

## 环境限制，本轮未覆盖

- 暗色模式、更新弹窗、扫码、审批卡片 UI：未测。
- 提问失败路径、前台保活失败路径：只有代码审查，没有运行时证据。

## 验证工具

`test_shots/` 下留了三个脚本（`.cookie` 是真实凭据，已删除，重跑需自行生成）：

- `ui.py` — dump 当前界面到可读表格（坐标 / class / enabled / clickable / 文本）。
- `probe.py sessions|find <title>|page <sid> [n]` — 直接查服务端会话日志，看 `turn/end.reason.kind`。
- `cancel_test.py "<prompt>"` — 自动「起长任务 → 等停止按钮 → 点击 → 比对服务端结束原因」，停止回归用这个。

模拟器注意：`adb shell input keyevent 4` 在输入法未打开时会退出 Activity；密集连发按键事件（如 80 个 DEL）会压垮输入分发造成 ANR。`cancel_test.py` 里已按这两点做了防护。

