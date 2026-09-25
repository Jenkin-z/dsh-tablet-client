# dsh_tablet_client 最小改造方案

## 目标

把现有 `dsh_tablet_client` 从"多个模块各自猜测状态"改为"单一权威状态源"，让状态与桌面端保持一致，同时保留现有功能骨架。

---

## 当前问题诊断

### 根本原因：状态来源分散

| 模块 | 自维护的状态 | 问题 |
|------|-------------|------|
| `SessionMonitor` | `running`, `online`, `sessions` | 轮询推断 |
| `ServerManager` | `groups`, `running`, `unviewed` | 二次聚合 |
| `ChatController` | `connected`, `agentRunning`, `sending` | 自己推断 |
| `ChatMessageMixin` | `streaming`, `activeTool` | 自己拼 |
| `ChatApprovalMixin` | `approvals`, `question` | 自己维护 |
| `MuxStream` | `sessionId`, `connected` | 自己管理 |

**问题**：6 个模块各自维护状态，互相推断，最终漂移。

---

## 改造方案

### 1. 新增 `DshSessionState`（状态中枢）

所有关键状态都从这个中枢读取，任何模块不能自己猜。

```dart
class DshSessionState {
  // 连接状态
  bool connected = false;
  bool connecting = false;
  String? connectionError;

  // 会话状态
  String? sessionId;
  String? sessionTitle;
  bool agentRunning = false;
  bool assistantStreaming = false;

  // 审批/提问
  List<PendingApproval> approvals = [];
  PendingQuestion? question;

  // 工具
  String? activeTool;
  ChangesTracker changes = ChangesTracker();

  // 事件
  DateTime? lastTurnEnd;
  DateTime? lastActivity;
}
```

### 2. 统一事件入口（`MuxEventDispatcher`）

所有 mux 事件先进同一个 dispatcher，再分发到状态中枢。

```dart
class MuxEventDispatcher {
  final DshSessionState state;
  
  void dispatch(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'session/status':
        state.agentRunning = data['running'] == true;
        break;
      case 'assistant/chunk':
        state.assistantStreaming = true;
        break;
      case 'assistant/message':
        state.assistantStreaming = false;
        break;
      case 'turn/end':
        state.agentRunning = false;
        state.assistantStreaming = false;
        state.lastTurnEnd = DateTime.now();
        break;
      // ...
    }
    state.notifyListeners();
  }
}
```

### 3. 控制台只做展示

`ConsoleScreen` 只从 `DshSessionState` 读状态，不再自己推断。

### 4. 砍掉本地推断补丁

删除所有"如果之前是 running，现在不是 running，就标完成"这类逻辑。

---

## 文件改动清单

### 必须改

| 文件 | 改动 |
|------|------|
| `lib/services/chat_controller.dart` | 删除自维护状态，改为从中枢读取 |
| `lib/services/chat_message_mixin.dart` | 删除状态推断，改为接收事件 |
| `lib/services/chat_approval_mixin.dart` | 删除自维护列表，改为从中枢读取 |
| `lib/services/session_monitor.dart` | 删除轮询推断，改为只做会话列表刷新 |
| `lib/services/server_manager.dart` | 删除二次聚合，改为只做服务器管理 |
| `lib/screens/console_screen.dart` | 删除自定义状态聚合，改为从中枢读取 |

### 必须新增

| 文件 | 用途 |
|------|------|
| `lib/services/dsh_session_state.dart` | 状态中枢 |
| `lib/services/mux_event_dispatcher.dart` | 事件统一入口 |

### 可以保留

| 文件 | 说明 |
|------|------|
| `lib/services/dsh_api.dart` | RPC 通信，保留 |
| `lib/services/mux_stream.dart` | WebSocket 连接，保留 |
| `lib/services/dsh_auth.dart` | 鉴权，保留 |
| `lib/services/settings_service.dart` | 设置，保留 |
| `lib/services/sound_service.dart` | 提示音，保留 |
| `lib/services/notification_service.dart` | 通知，保留 |
| `lib/screens/chat_screen.dart` | UI 骨架，保留 |
| `lib/screens/settings_screen.dart` | 设置页，保留 |
| `lib/widgets/*.dart` | 所有控件，保留 |

---

## 第一版止血方案（最小改动）

### 目标

让状态不再漂移，优先解决"不同步"问题。

### 步骤

1. 新建 `DshSessionState`
2. 新建 `MuxEventDispatcher`
3. 修改 `MuxStream`，事件先过 dispatcher
4. 修改 `ChatController`，删除自维护状态，改为从中枢读取
5. 修改 `ConsoleScreen`，删除自定义聚合，改为从中枢读取

### 预计工作量

- 新增 2 个文件
- 修改 4 个文件
- 总计约 200-300 行改动

---

## 后续优化（可选）

- 拆分 `ChatController` 为更小的模块
- 优化控制台 UI
- 添加更多服务器管理功能
- 优化重连逻辑

---

## 验证方式

1. 启动 DSH Desktop，开启局域网访问
2. 启动 `dsh_tablet_client`，连接到 DSH
3. 在桌面端发起任务，观察 app 状态是否同步
4. 在 app 中审批/提问，观察桌面端是否响应
5. 断开网络，观察重连后状态是否恢复