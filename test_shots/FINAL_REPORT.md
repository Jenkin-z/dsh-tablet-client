# DSH Tablet Client 综合测试报告

**版本**: 1.6.9+43 (Debug APK)  
**环境**: Android 模拟器 (API 34, 1920×1200), DSH Node 192.168.10.171:3080  
**测试时长**: ~3 小时, ~11 轮对话  
**Session**: `session-92053ac4-5ca4-44df-98e5-da3bad2a598a` (你好，我是小代码酱。)

---

## 🔴 P0 — 严重 Bug

### 1. 停止（Cancel）按钮完全不生效
**复现率**: 6/6 次（100%）  
**现象**: 点击「停止」后 Agent 继续运行直到自然完成，服务端 turn reason 始终为 `completed`，从未 `aborted`。  
**对比**: Python 直接调用 `session/cancel` 同一 session → 秒级返回 `accepted:true` + `reason:aborted`。  
**根因链**:
- App 的 `cancelSession` HTTP 请求延迟 15–30 秒才返回（vs Python 秒级），疑似 Dart HTTP 连接池复用已关闭的 keep-alive 连接导致 TCP 层重试
- `ChatController.cancel()` 完全忽略 `cancelSession` 返回的 `accepted` 字段 → 即使 host 返回 `accepted:false`，UI 也会假装成功
- 无 `accepted:false` 的用户提示

**影响**: 用户无法中断长任务，核心交互失效。

### 2. 用户消息气泡永久消失
**复现率**: 4/4 轮（100%），含 3 次独立确认  
**现象**: 用户发送的消息在 turn 完成后从聊天列表消失。服务端 `session/page` 确认 `user/message` 事件存在（seq 8/25/49/80/88/104/120/129 等）。  
**根因**: `onQueueUpdate` 的 `removeWhere(role=='user' && removed.contains(content))` 删除了乐观气泡，但服务端 `user/message` 回声被 echo dedup 抑制（`_pendingEchoRpc` / `_lastSentText` / seq dedup），无法补回。  
**证据**: 重连后用户消息重新出现（来自 `onMuxSnapshot` 的 `parseHistory`）。

---

## 🟠 P1 — 重要 Bug

### 3. 重复助手气泡
**复现率**: 至少 2 次  
**现象**: 同一条助手回复显示为两条气泡（部分流式 + 完整最终版）。服务端仅有 1 条 `assistant/message`。  
**根因**: `onAssistantFinal` 在流式气泡已通过 `flushDelta` finalize 后仍 append 新气泡（turn-end 竞态）。

### 4. 问题提交后弹层未及时关闭
**复现率**: 1/2 次  
**现象**: 第一次提交问题时 host 已收到答案（seq 28 tool/result），turn 跑到完成，但 QuestionSheet 在 +5 秒仍打开且「提交」按钮 enabled。  
**根因**: `respondQuestion` 返回 `false`（疑似 `$events/result` ok-flag 问题），snackbar 被 Sheet 遮挡。

### 5. 间歇性断连（无自动恢复 UI 反馈）
**复现率**: 2 次  
**现象**: 对话页突然 `connected=false`，发送按钮静默变灰，输入框禁用。无可见的重连状态指示。

---

## 🟡 P2 — 一般问题

### 6. 文件超限
- `chat_screen.dart`: 450 行（限制 400）
- `settings_screen.dart`: 428 行（限制 400）

### 7. 无障碍：输入框 hint 未暴露
- `ChatInputBar` 的 `TextField` hint `输入消息…` 在 a11y 树中无 `content-desc`。

### 8. 设置页开关点击目标不明确
- 「屏幕常亮」和「前台保活服务」Switch 的 a11y 中心在行中央（x=960），实际开关在右侧。3 次点击均未改变 `checked` 状态。

---

## ✅ 已验证正常

| 功能 | 状态 |
|------|------|
| Token 授权配对 | ✓ |
| 发送 → 流式响应 → 完成 | ✓ |
| 问题单渲染 + 选择 + 提交 | ✓ |
| 会话抽屉（列表、切换、新建、工作区分组） | ✓ |
| 标题自动更新 | ✓ |
| 通知 `dshm_events_v2`（11 次 posted） | ✓ |
| 控制台（刷新、会话列表、全部已读） | ✓ |
| 设置页（测试连接 → ✓） | ✓ |
| Token 授权（30 天 cookie） | ✓ |

---

## 🟠 P1 — 重要 Bug（续）

### 9. 变更（Changes）抽屉无法打开
**复现率**: 3/3 次  
**现象**: 变更按钮 `en=true`（connected=true），tap 精确命中按钮中心 (1776,104) 及偏移位置 (1740,140)，`endDrawer` 始终未打开。  
**根因**: `Builder` 上下文中 `Scaffold.of(drawerContext).openEndDrawer()` 可能未正确找到 ScaffoldState，或 `ChangesDrawer` 注册有问题。  
**影响**: 用户无法查看文件变更历史。

### 10. 前台保活服务开关无响应
**复现率**: 2/2 次  
**现象**: 开关行 `en=true`，tap 在 (1750,912) 未改变 `checked` 状态。`dumpsys activity services` 无 ServiceRecord。  
**对比**: 屏幕常亮开关在同一 x 位置 (1750,816) 成功切换 `checked=true`。  
**根因**: 开关 tap 目标不明确——a11y 中心在行中央 (960)，实际 toggle 在右侧但坐标不一致。

---

## 🟡 P2 — 一般问题（续）

### 11. BACK 键退出 App 到桌面
**现象**: 在对话页，若键盘未打开（如 connected=false 时输入框 disabled），按 BACK 键无 IME 可关 → 直接退出 Activity 到 Launcher。  
**影响**: 用户误触 BACK 会离开 App，且无确认提示。这是 Android 默认行为，但对监控类 App 可考虑拦截。

### 12. 间歇性断连后 Composer 静默禁用
**现象**: 断连时 `connected=false` → TextField `enabled=false` → 用户输入的文字无法发送（`input text` 写入无效），BACK 键退出 App。  
**影响**: 用户输入内容后点发送无反应，误以为 App 卡死。

---

## ✅ 已验证正常（续）

| 功能 | 状态 |
|------|------|
| 屏幕常亮开关 | ✓ checked=true 生效 |
| 冷启动恢复（force-stop → relaunch） | ✓ 会话保留、自动重连、消息恢复 |
| Token 授权（30 天 cookie） | ✓ |

1. **立即** `cancel()` — 检查 `accepted`，HTTP 超时缩短到 5s，失败显示 snackbar
2. **立即** `onQueueUpdate` — 不删除已确认的用户气泡，或在 `onUserMessage` 中绕过 dedup 补回
3. **高** `onAssistantFinal` — 检查已有流式气泡，避免重复 append
4. **中** 断连 — 添加可见的重连状态 banner