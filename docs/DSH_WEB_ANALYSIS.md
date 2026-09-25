# DSH 官方 Web 端接口深度分析 & Tablet Client 借鉴方案

> 基于 `D:\software\deepseek-harness\packages\api\` + `packages\client\` 源码分析

---

## 一、官方 Web 端架构（与 Tablet Client 对比）

```
官方 Web (apps/web)                    Tablet Client (Flutter)
─────────────────────                  ──────────────────────
AppWebEntry → Cordis 插件加载           main.dart → Provider 初始化
├─ ClientModules (插件图)               ├─ SettingsService (本地配置)
├─ API Gateway (Remote dispatch)       ├─ DshApi (手写 HTTP RPC)
├─ Connection (mux + HTTP bridge)      ├─ MuxStream (手写 WebSocket)
├─ SessionController (Client model)    ├─ ChatController (业务逻辑)
├─ WorkspaceController (Client model)  ├─ SessionMonitor (轮询)
├─ UI Slots (React 组件树)             ├─ Flutter Widgets
└─ Conversation (事件→视图)            └─ 无此层，直接解析事件
```

核心差异：**官方端是 Typert 自动生成的 Remote 调用 + Cordis 事件驱动，Tablet Client 是手写 HTTP RPC + 手动解析 WebSocket 帧**。

---

## 二、官方 Web 端完整 Remote 接口清单

### Session Controller (`session/*`)

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `session/list` | `(_request: {})` | `SessionSummary[]` | 列出所有会话（含投影、blank、cwd、parent） |
| `session/search` | `(query: string)` | `{ items, hasMore }` | **全文搜索**（Tablet 未使用） |
| `session/create` | `(sessionId?, cwd?, agentPreset?, workspaceId?)` | `{ sessionId, agentPreset? }` | 创建/复用会话 |
| `session/prompt` | `(requestId, sessionId, mode, content[], clientTimeZone?)` | `{ accepted }` | 发送提示词（支持 queue/steer 模式） |
| `session/page` | `(address, throughSeq, beforeSeq?, maxMessages?)` | `{ records, hasMore }` | 历史分页 |
| `session/follow` | `(address, assistantStream?, maxMessages?)` | **AsyncIterable** | 实时事件流（snapshot + events + assistant-stream） |
| `session/control` | `()` | **AsyncIterable** | **全局控制流**（queue/jobs/projection baseline） |
| `session/cancel` | `(sessionId)` | `{ accepted }` | 取消当前轮（保留 inbox） |
| `session/rename` | `(sessionId, title)` | `{ title, seq }` | **重命名**（Tablet 未使用） |
| `session/fork` | `(sessionId, atSeq?)` | `{ sessionId }` | **分叉会话**（Tablet 未使用） |
| `session/selectModel` | `(sessionId, provider, model, reasoningEffort?)` | `{ selected }` | **切换模型**（Tablet 未使用） |
| `session/updateQueue` | `(sessionId, itemId, action: edit\|remove\|steer)` | `{ accepted }` | **队列管理**（Tablet 未使用） |
| `session/attachment` | `(sessionId, attachmentId)` | `{ attachment, data(base64) }` | **图片附件读取**（Tablet 未使用） |

### Workspace Controller (`workspace/*`)

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `workspace/create` | `(path)` | `{ workspace, created }` | 创建工作区 |
| `workspace/rename` | `(workspaceId, title)` | `{ workspace }` | 重命名 |
| `workspace/delete` | `(workspaceId)` | `{ deleted }` | 删除 |
| `workspace/insertBefore` | `(workspaceId, beforeWorkspaceId?)` | `{ workspaceIds }` | 排序 |
| `workspace/insertSessionBefore` | `(workspaceId, sessionId, beforeSessionId?)` | `{ workspace }` | 会话排序 |
| `workspace/archiveSession` | `(sessionId)` | `{ archivedSessionIds }` | 归档（Tablet 已使用流） |
| `workspace/unarchiveSession` | `(sessionId)` | `{ archivedSessionIds }` | 取消归档 |

### Settings Controller (`settings/*`)

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `settings/describe` | `()` | `{ writable, hasDocument, namespaces[] }` | 读取所有配置 |
| `settings/update` | `(ns, patch, expectedRevision?)` | `SettingsNamespaceView` | 合并写入 |
| `settings/replace` | `(ns, section, expectedRevision?)` | `SettingsNamespaceView` | 全量替换 |
| `settings/mutate` | `(ns, ops[], expectedRevision?)` | `SettingsNamespaceView` | 路径编辑 |
| `settings/openSettingsDocument` | `(signal)` | `{ opened }` | 打开配置文件 |
| `settings/openAgentPresetDirectory` | `(agentPreset, signal)` | `{ opened, path? }` | 打开预设目录 |
| `settings/canOpenAgentPresetDirectory` | `()` | `boolean` | 检测能力 |

### Terminal Controller (`terminal/*`) — 9 个方法

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `terminal/environment` | `(agent, signal)` | `TerminalEnvironment` | 读取工作目录和终端限制 |
| `terminal/shells` | `(agent, signal)` | `TerminalShell[]` | 发现已安装的 shell |
| `terminal/list` | `(sessionId)` | `WebTerminalInfo[]` | 列出已保留的终端 |
| `terminal/create` | `(agent, request, signal)` | `WebTerminalInfo` | 创建交互式终端 |
| `terminal/follow` 🌊 | `(agent, id, attachmentId, signal)` | **AsyncIterable** | 终端输出流 |
| `terminal/write` | `(agent, id, attachmentId, data)` | `void` | 写入终端输入 |
| `terminal/resize` | `(agent, id, attachmentId, cols, rows)` | `void` | 调整终端尺寸 |
| `terminal/rename` | `(agent, id, title)` | `void` | 重命名终端 |
| `terminal/close` | `(agent, id)` | `Promise<void>` | 关闭终端 |

### Workspace Files (`workspaceFiles/*`) — 7 个方法

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `workspaceFiles/read` | `(scope, path, range, signal)` | `WorkspaceFileText` | 读取文件页面（文本） |
| `workspaceFiles/readBytes` | `(scope, path, range, signal)` | `WorkspaceFileBytes` | 读取字节窗口（base64） |
| `workspaceFiles/readAll` | `(scope, path, signal)` | `WorkspaceFileBytes` | 读取完整文件 |
| `workspaceFiles/readRelated` | `(scope, path, relativePath, signal)` | `WorkspaceFileBytes` | 读取关联文件 |
| `workspaceFiles/stat` | `(scope, path, signal)` | `WorkspaceFileStat` | 文件元信息（不含内容） |
| `workspaceFiles/list` | `(scope, path, signal)` | `WorkspaceDirectoryListing` | 列出目录子项 |
| `workspaceFiles/changes` 🌊 | `(scope, signal)` | **AsyncIterable** | 文件系统变更流 |

### Directory Picker (`directoryPicker/*`) — 3 个方法

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `directoryPicker/pick` | `(signal)` | `string \| null` | 打开 OS 目录选择器 |
| `directoryPicker/list` | `(path?, signal)` | `DirectoryListing` | 列出目录内容 |
| `directoryPicker/createDirectory` | `(path, name)` | `string` | 创建子目录 |

### Credentials (`credentials/*`) — 3 个方法

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `credentials/describe` | `(refs[])` | `Record<string, CredentialInfo>` | 批量描述凭据状态 |
| `credentials/set` | `(ref, value)` | `void` | 存储凭据 |
| `credentials/unset` | `(ref)` | `void` | 删除凭据 |

### Skills (`skills/*`) — 1 个方法

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `skills/list` | `(request, signal)` | `SkillListValue` | 列出可调用技能 |

### File References (`fileReferences/*`) — 1 个方法

| Remote 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `fileReferences/list` | `(agent, query, signal)` | `FileReferenceCandidate[]` | 文件路径自动补全 |

### 非 Remote HTTP 路由

| 路由 | 方法 | 说明 |
|---|---|---|
| `/api/file?path=<absolute>` | GET/HEAD | 从文件系统提供文件内容（需认证） |

---

## 三、官方 Web 端的 3 个关键流（Tablet 已使用的 + 未使用的）

### 流 1: `$events` — waterfall（审批/提问）
- **Tablet**: ✅ 已使用
- **官方额外**: 还有 `agentId` 字段（scoped 到具体 Agent）

### 流 2: `session/follow` — journal + assistant-stream
- **Tablet**: ✅ 已使用
- **官方额外**:
  - `snapshot` 帧包含 `header`（完整 SessionHeader）、`cursor`、`projections`（含 title、subagent 等）
  - `projections` 随 snapshot 一起下发，Tablet 只用了部分

### 流 3: `session/control` — 全局控制流
- **Tablet**: ❌ **未使用**
- **官方用途**:
  - `baseline`: 所有会话的 queue（待处理消息）、jobs（后台任务）、projections 实时快照
  - `queue` 帧: 单个会话的队列变更（用于编辑/删除/插入待处理消息）
  - `jobs` 帧: 后台任务状态（显示在侧栏）
  - `projection` 帧: 实时标题/模型等投影变更

### 流 4: `workspace/follow` — 工作区全量 + 增量
- **Tablet**: ✅ 已使用（只消费 `baseline.archivedSessionIds` 和 `archived` 帧）
- **官方完整协议**:
  - `baseline` 帧: `{ items: WorkspaceView[], archivedSessionIds }` — 全量工作区列表 + 归档
  - `upsert` 帧: `{ workspace: WorkspaceView }` — 新增/更新一个工作区
  - `remove` 帧: `{ workspaceId }` — 删除一个工作区
  - `order` 帧: `{ workspaceIds: string[] }` — 工作区排序变更
  - `archived` 帧: `{ archivedSessionIds: string[] }` — 归档列表变更

### 流 5: `workspaceFiles/changes` — 文件系统监控
- **Tablet**: ❌ **未使用**（Tablet 通过 view 槽间接获取 diff）
- **官方用途**: 实时监控工作区内文件变更，推送 `change` 帧（含 `absolutePath` + `version` 或 `absent: true`）

---

## 五、完整错误码词汇表

| 错误码 | 命名空间 | 含义 |
|---|---|---|
| `workspace/invalid-path` | workspace | 路径无效 |
| `workspace/name-conflict` | workspace | 名称冲突 |
| `workspace/not-found` | workspace | 工作区不存在 |
| `settings/rejected` | settings | 写入被拒绝 |
| `settings/conflict` | settings | 并发写入冲突 |
| `session/model-unavailable` | session | 模型不可用 |
| `session/conflict` | session | 会话冲突（cwd 不匹配） |
| `session/agent-busy` | session | Agent 忙碌 |
| `session/not-found` | session | 会话不存在 |
| `session/attachment-invalid` | session | 附件无效 |
| `session/queue-item-not-found` | session | 队列项不存在 |
| `session/steer-unavailable` | session | steering 不可用 |
| `session/title-invalid` | session | 标题无效 |
| `session/fork-unavailable` | session | 分叉不可用 |
| `gateway/cancelled` | gateway | 操作被取消 |
| `gateway/internal` | gateway | 内部错误 |
| `gateway/bad-request` | gateway | 请求格式错误 |
| `subagent/not-found` | session | 子代理不存在 |

---

## 六、Tablet Client 可借鉴的优化方案

```typescript
// stream-client.ts 中的关键设计
class RemoteStreamMuxClient {
  // 1. 物理连接管理
  start(): void           // 确保存在一次物理连接尝试
  reconnect(): void       // 取消当前 socket，立即开始新尝试
  
  // 2. 逻辑流独立
  async *open(endpoint, payload, signal): AsyncGenerator  // 每个逻辑流独立生命周期
  
  // 3. 错误分类
  RemoteStreamCarrierError   // 物理层错误（可重试）
  RemoteError                // 业务层错误（不重试）
}
```

**关键洞察**:
1. 物理 WebSocket 断开时，所有逻辑流收到 `RemoteStreamCarrierError`
2. Connection 层决定哪些流可以重试（持久 journal 用 seq 恢复，瞬态 control 用 baseline 替换）
3. `clientId` 在 `$events` ready 帧中获取，与物理 socket 绑定
4. 重连时，旧 `clientId` 立即失效，新 ready 帧提供新 `clientId`

---

## 五、Tablet Client 可借鉴的优化方案

### 🔴 P0 — 高价值、低风险

#### 1. 引入 `session/control` 流（替代轮询）

**现状**: `ServerManager` 每 8s 轮询 `session/list` 获取 `running` 状态和队列信息。

**官方方案**: `session/control` 流一次性推送所有会话的 queue、jobs、projections baseline，之后增量更新。

**借鉴收益**:
- 消除 8s 轮询，减少 90% 的 HTTP 请求
- 实时获取标题变更（projection 帧）
- 获取后台任务列表（jobs 帧，如子进程、下载等）
- 队列管理能力（编辑/删除待处理消息）

**实现方案**:
```dart
// 在 MuxStream 中新增第 4 条逻辑流
_send({
  'type': 'open',
  'streamId': 'ctl',
  'endpoint': 'session/control',
  'payload': {'args': {}},
});

// 处理 baseline 帧
void _onControlFrame(Map<String, dynamic> value) {
  switch (value['type']) {
    case 'baseline':
      // { queues: {sessionId: [...]}, jobs: {sessionId: [...]}, projections: {...} }
      onControlBaseline?.call(value['value']);
      break;
    case 'queue':
      // { sessionId, items: [...] }
      onQueueUpdate?.call(/*...*/);
      break;
    case 'jobs':
      // { sessionId, jobs: [...] }
      onJobsUpdate?.call(/*...*/);
      break;
    case 'projection':
      // { sessionId, key, value, seq }
      onProjectionChange?.call(/*...*/);
      break;
  }
}
```

#### 2. WebSocket 重连机制改进（对齐官方 `RemoteStreamMuxClient`）

**现状**: `MuxStream` 断线后由 `ChatController` 外部重建整个实例。

**官方方案**: `RemoteStreamMuxClient` 内置物理连接管理，逻辑流通过 `open()` 独立挂载。

**借鉴方案**:
```dart
class MuxStream {
  // 物理连接生命周期
  int _revision = 0;
  
  void reconnect() {
    _revision++;
    _channel?.sink.close(4000, 'reconnect');
    _channel = null;
    _failAllStreams();  // 通知所有逻辑流
    _connect();         // 立即重连
  }
  
  // 逻辑流通过 streamId 独立管理
  // 重连后自动重新打开 $events + session/follow + workspace/follow + session/control
  void _onConnected() {
    _openEventsStream();
    if (sessionId != null) _openFollowStream(sessionId!);
    _openWorkspaceStream();
    _openControlStream();  // 新增
  }
}
```

#### 3. `session/follow` 的 `projections` 用于实时标题

**现状**: 标题从 `session/list` 的响应中提取，8s 刷新一次。

**官方方案**: `session/follow` 的 `snapshot` 帧包含 `projections.values.title`，实时更新。

**借鉴收益**: 切换会话或重连后立即获得正确标题，无需等待下一次轮询。

```dart
void _onFollowSnapshot(Map<String, dynamic> value) {
  // 现有逻辑...
  final projections = value['projections'];
  if (projections is Map) {
    final values = projections['values'];
    if (values is Map) {
      final title = values['title'];
      onTitleUpdate?.call(sessionId, title);  // 实时标题
    }
  }
}
```

---

### 🟡 P1 — 中等价值

#### 4. 利用 `session/search` 做本地搜索

**现状**: 无搜索功能。

**官方方案**: `session/list` 支持 `search(query)` 方法，返回 `SessionSearchItem[]`（含 snippet）。

**借鉴收益**: 用户可以搜索历史对话内容，快速定位会话。

```dart
// DshApi 新增
Future<List<Map<String, dynamic>>> searchSessions(String query) async {
  final value = await _rpc('session/list', {
    'request': {'query': query},  // 带 query 参数走 search 分支
  });
  return (value['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
}
```

#### 5. `session/rename` 支持重命名

**现状**: 无法重命名会话。

**官方方案**: `session/rename(sessionId, title)` → `{ title, seq }`。

#### 6. `session/updateQueue` 队列管理

**现状**: 队列消息只展示，无法编辑/删除。

**官方方案**: `session/updateQueue(sessionId, itemId, action)` 支持 edit/remove/steer。

**借鉴收益**: 用户可以在平板上删除误发的消息或编辑待处理的提示词。

#### 7. 审批应答增加 `next` 模式

**现状**: 审批应答只支持 `allowed-once` 和 `rejected`。

**官方方案**: `$events/result` 的 `outcome.kind` 还支持 `next`（传递给下一个处理器）。

---

### 🟢 P2 — 长期架构改进

#### 8. 引入 Client Model 层（对齐官方 `SessionManager`）

**现状**: `ChatController` 同时承担 UI 状态管理、网络通信、消息解析。

**官方方案**: 三层分离：
- `SessionManager`（Client model）: 拥有 session list baseline、queue、projection store
- `Session`（单会话 model）: 拥有 event window、pagination、follow state
- UI adapter: 把 model observable 转换为 UI 数据

**借鉴收益**: 职责清晰，可测试性提升，支持多设备同步。

#### 9. Workspace 操作完整化

**现状**: 只消费 `workspace/follow` 的归档列表。

**官方方案**: 完整的 workspace CRUD（create/rename/delete/insertBefore/archiveSession/unarchiveSession）。

#### 10. 会话分叉（`session/fork`）

**现状**: 无法从历史点重新开始。

**官方方案**: `session/fork(sessionId, atSeq?)` 从指定 turn 创建新会话。

---

## 六、接口覆盖度对比

| 功能域 | 官方 Web 端 | Tablet Client | 差距 |
|---|---|---|---|
| **会话列表** | ✅ list + search | ✅ list | 缺 search |
| **创建会话** | ✅ 含 agentPreset/workspaceId | ✅ 基础 | OK |
| **发送提示** | ✅ queue/steer + 图片 + 时区 | ✅ queue only | 缺 steer/图片 |
| **历史分页** | ✅ page + follow | ✅ 两者都有 | OK |
| **实时事件流** | ✅ follow + control | ✅ follow only | **缺 control** |
| **审批/提问** | ✅ 完整 | ✅ 完整 | OK |
| **取消运行** | ✅ | ✅ | OK |
| **重命名** | ✅ | ❌ | 缺 |
| **分叉会话** | ✅ | ❌ | 缺 |
| **切换模型** | ✅ | ❌ | 缺 |
| **队列管理** | ✅ edit/remove/steer | ❌ | 缺 |
| **图片附件** | ✅ 读取历史图片 | ❌ | 缺 |
| **Workspace 管理** | ✅ 完整 CRUD | ✅ 只读归档 | 缺写操作 |
| **设置管理** | ✅ describe/update/replace | ❌ | 缺 |
| **终端** | ✅ | ❌ | 不需要 |
| **全文搜索** | ✅ | ❌ | 缺 |

---

## 七、实施优先级路线图

```
Phase 1 (1-2 周): 核心体验提升
├─ [ ] 引入 session/control 流（替代轮询）
├─ [ ] WebSocket 重连机制改进
└─ [ ] projections 实时标题

Phase 2 (2-3 周): 功能补全
├─ [ ] session/search 搜索
├─ [ ] session/rename 重命名
├─ [ ] session/updateQueue 队列管理
└─ [ ] 审批应答 next 模式

Phase 3 (长期): 架构升级
├─ [ ] Client Model 层分离
├─ [ ] Workspace CRUD
└─ [ ] session/fork 分叉
```

---

## 八、关键代码参考

| 功能 | 官方源码路径 | Tablet 对应 |
|---|---|---|
| Mux 物理连接 | `packages/api/gateway/src/client/stream-client.ts` | `lib/services/mux_stream.dart` |
| Session 流协议 | `packages/api/gateway/src/stream-protocol.ts` | 无独立定义，嵌入 mux_stream.dart |
| Session 历史/跟随 | `packages/api/session-controller/src/history.ts` | `lib/services/mux_session_handler.dart` |
| Session 控制流 | `packages/api/session-controller/src/control.ts` | **不存在** |
| Session 命令 | `packages/api/session-controller/src/commands.ts` | `lib/services/dsh_api.dart` |
| Session 列表 | `packages/api/session-controller/src/list.ts` | `lib/services/session_monitor.dart` |
| Workspace 命令 | `packages/api/workspace-controller/src/commands.ts` | 无 |
| 设置管理 | `packages/api/settings-controller/src/index.ts` | 无 |