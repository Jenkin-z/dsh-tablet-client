# DSH Tablet Client — 接口文档 & 优化方案

> 基于代码分析 + DSH 官方文档，2026-03

---

## 一、架构总览

```
┌─────────────────────────────────────────────────────────┐
│                    DSH Tablet (Flutter)                   │
├─────────────────────────────────────────────────────────┤
│  UI 层 (Screens/Widgets)                                 │
│  ├─ ChatScreen ─ ChatController (ChangeNotifier)         │
│  ├─ ConsoleScreen ─ ServerManager (轮询聚合)              │
│  └─ SettingsScreen / PairScreen / QrScanScreen            │
├─────────────────────────────────────────────────────────┤
│  服务层                                                   │
│  ├─ DshApi          HTTP RPC 客户端（POST /api/*）        │
│  ├─ MuxStream       WebSocket mux（ws://.../api/remote.mux）│
│  ├─ NativeAuth      启动令牌 → browser cookie 换取       │
│  ├─ SessionMonitor  单台 PC 会话轮询                      │
│  ├─ ServerManager   多 PC 聚合                            │
│  ├─ UpdateService   APK 更新检查/下载/安装                │
│  └─ SettingsService 本地持久化                             │
└─────────────────────────────────────────────────────────┘
         │                    │
    HTTP POST /api/*     ws://host:3080/api/remote.mux
         │                    │
         ▼                    ▼
┌─────────────────────────────────────────────────────────┐
│              DSH Host (dsh web, port 3080)               │
│  ┌──────────────┐  ┌─────────────────────────────────┐  │
│  │ WebServer     │  │ Typert API Gateway              │  │
│  │ (node:http)   │  │ POST /api/<ns>/<method>         │  │
│  │ cookie auth   │  │ → Remote dispatch               │  │
│  └──────────────┘  └─────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Mux WebSocket (/api/remote.mux)                   │   │
│  │ ├─ $events (waterfall: approval, questions)       │   │
│  │ ├─ session/follow (journal + assistant-stream)    │   │
│  │ └─ workspace/follow (归档列表)                    │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 二、接口清单

### 1. 授权层

#### 1.1 `GET /?token=<launch-token>` — 换取 browser cookie

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_auth.dart` |
| 方法 | `NativeAuth.exchangeCookie(PairTarget)` |
| HTTP | `GET http://<host>:3080/?token=<token>` |
| 响应 | `303` + `Set-Cookie: dsh-auth-xxx=...` |
| Cookie 有效期 | ~30 天，DSH 重启后仍有效 |
| 失败处理 | 401=令牌过期，403=被拒绝 |

#### 1.2 `GET http://<host>:8099/launch-token.json` — 自动获取最新令牌

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_auth.dart` |
| 方法 | `NativeAuth.fetchFromRelay(host, port: 8099)` |
| HTTP | `GET http://<host>:8099/launch-token.json` |
| 响应 | `{ "token": "r_..." }` |
| 超时 | 10s |
| 用途 | 自动配对，无需手动粘贴启动链接 |

---

### 2. HTTP RPC 层 (`DshApi`)

所有 RPC 调用走统一信封格式：

```
POST http://<host>:3080/api/<method>
Cookie: dsh-auth-xxx=...
Content-Type: application/json

{
  "type": "client-request",
  "rpcId": "<uuid>",
  "method": "<method>",
  "payload": {
    "args": { ... }
  }
}

响应：
{
  "result": {
    "ok": true,
    "value": { ... }
  }
}
```

#### 2.1 `session/list` — 列出所有会话

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_api.dart` line 74 |
| 方法 | `listSessions()` |
| RPC | `POST /api/session/list` |
| 参数 | `{ "_request": {} }` |
| 返回 | `{ "items": [ { sessionId, cwd, updatedAt, running, blank, projections, ... } ] }` |
| 超时 | 30s |
| 用途 | 控制台轮询、会话侧栏、标题提取 |

#### 2.2 `session/create` — 创建新会话

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_api.dart` line 80 |
| 方法 | `createSession({cwd?, agentPreset?, workspaceId?})` |
| RPC | `POST /api/session/create` |
| 参数 | `{ "request": { "cwd"?, "agentPreset"?, "workspaceId"? } }` |
| 返回 | `{ "sessionId": "..." }` |
| 超时 | 30s |

#### 2.3 `session/prompt` — 发送提示词

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_api.dart` line 91 |
| 方法 | `sendPrompt(sessionId, text)` |
| RPC | `POST /api/session/prompt` |
| 参数 | `{ "request": { "requestId": "<uuid>", "sessionId": "...", "mode": "queue", "content": [{"type":"text","text":"..."}] } }` |
| 返回 | 成功/失败（客户端自生成 requestId 用于回声对账） |
| 超时 | 30s |

#### 2.4 `session/page` — 历史分页

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_api.dart` line 107 |
| 方法 | `getHistory(sessionId, {throughSeq?, beforeSeq?, maxMessages?})` |
| RPC | `POST /api/session/page` |
| 参数 | `{ "request": { "address": {"kind":"session","sessionId":"..."}, "throughSeq": -1, "beforeSeq"?, "maxMessages"? } }` |
| 返回 | `{ "records": [...], "hasMore": bool }` |
| 超时 | 30s |
| 用途 | 会话验证（maxMessages=1）、快照加载 |

#### 2.5 `session/cancel` — 取消当前轮

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/dsh_api.dart` line 122 |
| 方法 | `cancelSession(sessionId)` |
| RPC | `POST /api/session/cancel` |
| 参数 | `{ "request": { "sessionId": "..." } }` |
| 返回 | `{ "accepted": true/false }` |
| 超时 | 5s |
| 用途 | 用户点击"停止"按钮 |

---

### 3. WebSocket Mux 层 (`MuxStream`)

#### 3.1 `ws://<host>:3080/api/remote.mux` — 主 WebSocket 连接

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/mux_stream.dart` |
| 连接 | `IOWebSocketChannel.connect(wsBaseUrl + '/api/remote.mux')` |
| 认证 | `Cookie: dsh-auth-xxx=...` (upgrade header) |
| Ping | `pingInterval: 20s` |
| 自动重连 | 指数退避：前5次 3s，之后 30s |

**外层帧格式**：

```json
{ "type": "item", "streamId": "evt|fol|wfo", "value": { ... } }
{ "type": "error|end", "streamId": "evt|fol" }
```

**三种逻辑流**：

| streamId | endpoint | 用途 |
|---|---|---|
| `evt` | `$events` | 审批/提问 waterfall 应答 |
| `fol` | `session/follow` | 会话 journal + assistant-stream 打字机帧 |
| `wfo` | `workspace/follow` | 归档会话列表 |

---

#### 3.2 `$events` 流 — 审批与提问

**Opening frame**:

```json
{
  "type": "open",
  "streamId": "evt",
  "endpoint": "$events",
  "payload": { "args": {} }
}
```

**收到的 waterfall 帧**:

```json
{
  "type": "waterfall",
  "event": "approval/request",       // 或 "user-questions/request"
  "eventId": "...",
  "request": {
    "callId": "...",
    "toolName": "bash",
    "reason": "..."
  }
}
```

**收到的 cancel 帧**（已别处应答）:

```json
{
  "type": "cancel",
  "eventId": "..."
}
```

---

#### 3.3 `session/follow` 流 — 会话事件

**Opening frame**:

```json
{
  "type": "open",
  "streamId": "fol",
  "endpoint": "session/follow",
  "payload": {
    "args": {
      "request": {
        "address": { "kind": "session", "sessionId": "..." },
        "assistantStream": true,
        "maxMessages": 60
      }
    }
  }
}
```

**收到的帧类型**:

| type | 含义 | 处理 |
|---|---|---|
| `ready` | 客户端就绪 | 记录 `clientId` |
| `snapshot` | 快照（含 cursor） | 清空消息，回填历史 |
| `event` | journal event | 分发：user/message, assistant/message, tool/call, tool/result, turn/end |
| `assistant-stream` | 打字机增量 | `text-delta` chunk |
| `emit` | 广播事件 | `api-session/status`, `api-session/error` |

**Journal event 类型**:

| type | data | 含义 |
|---|---|---|
| `user/message` | `{content, source.rpcId, seq}` | 用户消息 |
| `assistant/message` | `{message.content}` | 助手最终消息 |
| `assistant/chunk` | `{chunk.type, chunk.text}` | 流式增量 |
| `tool/call` | `{name}` | 工具调用开始 |
| `tool/result` | `{}` | 工具调用完成 |
| `turn/end` | `{reason}` | 轮次结束（含错误信息） |

---

#### 3.4 `workspace/follow` 流 — 归档列表

**Opening frame**:

```json
{
  "type": "open",
  "streamId": "wfo",
  "endpoint": "workspace/follow",
  "payload": { "args": {} }
}
```

**收到的帧类型**:

| type | 含义 |
|---|---|
| `baseline` | `{ value: { archivedSessionIds: [...] } }` |
| `archived` | `{ archivedSessionIds: [...] }` |

---

### 4. HTTP 应答层 (`$events/result`)

#### 4.1 审批应答

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/mux_stream.dart` line 332 |
| 方法 | `respondApproval(eventId, allow)` |
| HTTP | `POST http://<host>:3080/api/$events/result` |
| 参数 | `{ "clientId": "...", "eventId": "...", "outcome": { "kind": "result", "value": "allowed-once" \| "rejected" } }` |
| 超时 | 15s |

#### 4.2 提问应答

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/mux_stream.dart` line 376 |
| 方法 | `respondQuestion(eventId, answers)` |
| HTTP | `POST http://<host>:3080/api/$events/result` |
| 参数 | `{ "clientId": "...", "eventId": "...", "outcome": { "kind": "result", "value": { "answers": [{ "id": "...", "selected": ["..."], "custom": "..." }] } } }` |
| 超时 | 15s |

---

### 5. 更新检查层

#### 5.1 `GET http://<host>:8099/version.json` — 版本检查

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/update_service.dart` |
| HTTP | `GET http://<host>:8099/version.json` |
| 响应 | `{ "versionCode": 29, "versionName": "1.5.2", "size": 52500000, "changelog": "...", "force": false, "url": "..." }` |
| 超时 | 8s |

#### 5.2 `GET http://<host>:8099/dsh-agent.apk` — APK 下载

| 属性 | 值 |
|---|---|
| 文件 | `lib/services/update_service.dart` line 99 |
| HTTP | `GET http://<host>:8099/dsh-agent.apk` |
| 超时 | 连接 10s / 请求 20s / 分块 30s |
| 特性 | 进度回调、流式写入 |

---

## 三、数据流完整路径

```
用户输入 → ChatController.send(text)
    │
    ├─ DshApi.sendPrompt(sessionId, text)
    │   └─ POST /api/session/prompt → 乐观气泡 + 回声对账
    │
    ├─ MuxStream (WebSocket)
    │   ├─ snapshot → 历史回填
    │   ├─ user/message → 回声确认
    │   ├─ assistant-stream chunk → 打字机效果
    │   ├─ assistant/message → 最终消息
    │   ├─ tool/call + tool/result → 工具状态
    │   ├─ turn/end → 轮次完成
    │   ├─ waterfall approval/request → 审批卡片
    │   ├─ waterfall user-questions/request → 提问弹窗
    │   └─ emit api-session/status → 运行状态
    │
    └─ 审批/提问 → POST /api/$events/result
```

---

## 四、优化方案

### 🔴 P0 — 高优先级

#### 1. WebSocket 重连逻辑改进

**现状**: `mux_stream.dart` 中断线后由 `ChatController._scheduleReconnect()` 重建整个连接，包括重新创建 `MuxStream` 实例。

**问题**: 
- 重连时丢失 `clientId`，导致 `$events/result` 失败
- 重连时审批卡片被清空再重新投递，闪烁

**建议**:
```
采用 DSH 官方文档推荐的 generation 恢复模型：
1. MuxStream 内置自动重连（指数退避 2s → 4s → 8s → ... → 60s max）
2. 重连时保持 clientId（或从 Host 获取新 clientId 后自动切换）
3. snapshot 帧做 seq 校验：新 snapshot 的 seq 必须 ≥ lastCursor，否则丢弃
```

#### 2. RPC 错误处理标准化

**现状**: `dsh_api.dart` 的 `_rpc()` 方法直接抛 `Exception('RPC Error [code]: message')`，上层 catch 用字符串判断。

**问题**: 无法区分网络错误 vs 业务错误 vs 授权过期。

**建议**:
```dart
// 新增 DshRpcException 类
class DshRpcException implements Exception {
  final String code;
  final String message;
  final int httpStatus;
  DshRpcException({required this.code, required this.message, this.httpStatus = 0});
}

// _rpc() 中：
if (result['ok'] != true) {
  final error = result['error'] as Map<String, dynamic>;
  throw DshRpcException(
    code: error['code'] as String? ?? 'unknown',
    message: error['message'] as String? ?? '未知错误',
  );
}
```

#### 3. session/list 响应的 projections 解析安全化

**现状**: `session_format.dart` 和 `chat_session_mixin.dart` 中直接访问 `s['projections']['values']['title']`，多层嵌套无空安全。

**问题**: Host 版本升级后 projections 格式可能变化，导致崩溃。

**建议**:
```dart
// 提取为安全访问函数（已有 sessionTitleOf，但 titleFor 重复实现了）
String? safeProjectionTitle(Map<String, dynamic> session) {
  try {
    final proj = session['projections'];
    if (proj is! Map) return null;
    final values = proj['values'];
    if (values is! Map) return null;
    final t = values['title'];
    if (t is String && t.isNotEmpty) return t;
    if (t is Map) return t['title'] as String?;
    return null;
  } catch (_) {
    return null;
  }
}
```

---

### 🟡 P1 — 中优先级

#### 4. 合并 session/list 轮询与 mux 实时推送

**现状**: `ServerManager` 每 8s 轮询 `session/list`，同时 mux `$events` 也推送 `api-session/status`。

**问题**: 
- 两种来源的 `running` 状态可能冲突（轮询刚拿到 running=false，mux 又推 running=true）
- 8s 轮询对监控台来说太频繁（DSH 官方文档的 Client model 是 stream 优先）

**建议**:
```
根据 DSH 官方 Web Client 架构文档：
1. 对于活跃的聊天会话：完全依赖 mux 实时推送
2. 对于监控台列表：首次加载用 session/list，之后完全依赖
   session/status + session/error 推送
3. 仅在 mux 断线期间降级为轮询（保持 8s 间隔）
4. 重连后立即做一次 session/list 刷新
```

#### 5. 审批/提问应答增加重试机制

**现状**: `_postEventResult()` 失败后只打印日志，不重试。

**问题**: 网络抖动导致审批应答丢失，用户操作被忽略。

**建议**:
```dart
Future<bool> _postEventResult(String eventId, Object value, {int retries = 3}) async {
  for (var i = 0; i < retries; i++) {
    try {
      final ok = await _doPost(eventId, value);
      if (ok) return true;
    } catch (_) {}
    if (i < retries - 1) {
      await Future.delayed(Duration(seconds: (i + 1) * 2));
    }
  }
  return false;
}
```

#### 6. 历史快照加载优化

**现状**: `onMuxSnapshot()` 完全清空 `messages` 再重建，导致 UI 闪烁。

**问题**: 切换会话或重连时，消息列表瞬间变空再填满。

**建议**:
```dart
void onMuxSnapshot(List<Map<String, dynamic>> records) {
  final parsed = parseHistory(records);
  final newIds = parsed.map((p) => p.id).toSet();
  final oldIds = messages.map((m) => m.id).toSet();
  
  // 增量更新而非全量替换
  if (newIds.containsAll(oldIds) && oldIds.containsAll(newIds)) {
    // 内容完全相同，跳过
    return;
  }
  
  // 否则做 diff 替换
  messages.clear();
  messages.addAll(parsed.map(...));
  notifyListeners();
}
```

---

### 🟢 P2 — 低优先级 / 长期改进

#### 7. 利用 DSH session/query API 做本地搜索

**现状**: 没有使用 DSH 的 `session/query` 子系统（全文搜索、会话谱系、语义文档）。

**建议**: 
- 新增搜索页面，调用 `session/search` (对应 `ctx.sessionQuery.searchSessions`)
- 支持按文本搜索历史消息
- 支持按时间/类型过滤事件

#### 8. 利用 DSH session/projection 做实时标题更新

**现状**: 标题只在 `session/list` 响应时更新，mux 事件中不包含 projection 变更。

**建议**: 监听 mux 的 projection 更新帧，实时刷新标题。当前 `snapshot` 帧已包含 `projections`，但没有单独订阅 projection delta。

#### 9. Cookie 存储加密

**现状**: `dsh-auth-*` cookie 以明文存在 SharedPreferences。

**建议**: 使用 `flutter_secure_storage` 存储敏感凭据。

#### 10. Diff 计算移至 Isolate

**现状**: `diff_util.dart` 的 LCS 算法在主线程运行，大文件（>4000行）会阻塞 UI。

**建议**: 使用 `compute()` 或 `Isolate.spawn` 将 diff 计算移至后台线程。

#### 11. 增加 Workspace 操作

**现状**: 只消费 `workspace/follow` 的归档列表，没有创建/管理 workspace 的功能。

**建议**: 
- 新增 `workspace/create` RPC（需确认 DSH 是否支持）
- 会话拖拽分组

---

## 五、接口与 DSH 官方文档对照

| DSH 官方概念 | Tablet Client 对应 | 差距 |
|---|---|---|
| `SessionEvent` (user/message, assistant/message, tool/call, tool/result, turn/end) | ✅ 全部消费 | 无 |
| `session/list` (SessionRecord) | ✅ listSessions() | projections 解析不安全 |
| `session/create` | ✅ createSession() | 未用 agentPreset/workspaceId |
| `session/prompt` (queue mode) | ✅ sendPrompt() | 无 |
| `session/page` (throughSeq/beforeSeq) | ✅ getHistory() | 仅用于验证 |
| `session/cancel` | ✅ cancelSession() | 无 |
| `session/follow` (journal stream) | ✅ MuxStream.fol | 无 |
| `workspace/follow` (archived IDs) | ✅ MuxStream.wfo | 仅读归档，不管理 |
| `session/search` (全文搜索) | ❌ 未使用 | **可新增** |
| `session/projection` (实时标题) | 部分 | 通过 snapshot 被动获取 |
| `session/reference` (会话引用) | ❌ 未使用 | 不需要 |
| `session/title` (标题观察) | ❌ 未使用 | 可用于标题实时更新 |
| `$events` waterfall (approval/question) | ✅ 全部消费 | 无 |
| Typert API Gateway 信封格式 | ✅ 正确使用 | 无 |
| Cookie 认证 (browser-session) | ✅ NativeAuth | 存储未加密 |

---

## 六、关键配置建议

### 超时配置（当前值 vs 建议值）

| 参数 | 当前值 | 建议值 | 原因 |
|---|---|---|---|
| `httpTimeout` | 30s | 20s | 监控台场景响应应更快 |
| `cancelTimeout` | 5s | 8s | cancel 有时 Host 处理慢 |
| `pollInterval` | 8s | 15s (mux活跃时) / 5s (mux断线时) | 动态调整减少负载 |
| `reconnectFastDelaySec` | 3s | 2s | 更快恢复 |
| `reconnectSlowDelaySec` | 30s | 60s | 长时间断线减小负载 |
| `deltaFlushInterval` | 120ms | 80ms | 更流畅的打字机效果 |

### 内存优化

| 项目 | 当前 | 建议 |
|---|---|---|
| 消息列表 | 无上限 | 限制 200 条，超出部分分页加载 |
| changes 文件 | 100 文件上限 | ✅ 已有，合理 |
| sessions 轮询缓存 | 每次全量替换 | diff 更新，减少 GC 压力 |

---

## 七、总结

当前 Tablet Client 的 DSH 接口使用**覆盖度约 70%**，核心功能（会话列表、创建、提示词、历史、取消、流式消息、审批/提问、workspace 归档）全部正确实现。主要改进方向：

1. **连接稳定性**: mux 自动重连 + generation 恢复
2. **错误处理**: 标准化 RPC 异常 + 审批应答重试
3. **性能**: 合并轮询/推送、增量快照、diff 异步化
4. **功能扩展**: 利用 session/search、session/title 等未使用的 API
5. **安全**: Cookie 加密存储