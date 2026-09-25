# dsh_tablet_client 改造完成总结

## 改造目标

把 `dsh_tablet_client` 从"多个模块各自猜测状态"改为"单一权威状态源"，解决状态不同步问题。

## 核心改动

### 1. 新增状态中枢

**文件**: `lib/services/dsh_session_state.dart`

- 所有关键状态都从这里读取
- 任何模块不能自己猜状态
- 所有 mux 事件都必须先进 `MuxEventDispatcher`，再更新这个中枢

**包含的状态**:
- 连接状态: `connected`, `connecting`, `connectionError`
- 会话状态: `sessionId`, `sessionTitle`, `agentRunning`, `assistantStreaming`
- 审批/提问: `approvals`, `question`, `questionDialogOpen`
- 工具: `activeTool`, `changes`
- 会话列表: `sessions`, `loadingSessions`, `archivedIds`

### 2. 统一事件入口

**文件**: `lib/services/mux_event_dispatcher.dart`

- 所有 mux 事件都先进这里，再分发到状态中枢
- 不要在其他模块里自己处理 mux 事件
- 所有事件都必须通过这个 dispatcher 分发

**处理的事件**:
- 快照: `onSnapshot`
- 流式增量: `onTextDelta`
- 助手消息: `onAssistantMessage`
- 用户消息: `onUserMessage`
- 工具调用: `onToolCall`, `onToolResult`, `onToolView`
- Turn 生命周期: `onTurnEnd`
- 审批/提问: `onApproval`, `onApprovalResolved`, `onQuestion`, `onQuestionResolved`
- 队列/工作区: `onQueueUpdate`, `onWorkspaceBaseline`

### 3. 重构核心文件

#### ChatController (`lib/services/chat_controller.dart`)

**改动**:
- 删除自维护状态，改为从 `DshSessionState` 读取
- 所有 mux 事件都通过 `MuxEventDispatcher` 分发
- 不再自己维护业务状态

**保留**:
- 会话操作: `switchSession`, `createNewSession`
- 发送/取消: `send`, `cancel`
- 审批/提问: `answerApproval`, `submitQuestion`

#### MuxStream (`lib/services/mux_stream.dart`)

**改动**:
- 删除自维护状态，改为通过回调分发事件
- 所有事件都通过回调分发到 `MuxEventDispatcher`
- 不再自己维护业务状态

**保留**:
- WebSocket 连接管理
- 重连逻辑
- 事件应答

#### SessionMonitor (`lib/services/session_monitor.dart`)

**改动**:
- 删除轮询推断，改为只做会话列表刷新
- 状态推断全部交给 `DshSessionState` 和 `MuxEventDispatcher`

**保留**:
- 会话列表刷新
- 实时状态推送

#### ServerManager (`lib/services/server_manager.dart`)

**改动**:
- 删除二次聚合，改为只做服务器管理
- 不再自己推断状态

**保留**:
- 服务器管理
- 会话列表刷新
- 分组逻辑

### 4. 重构 UI 文件

#### ConsoleScreen (`lib/screens/console_screen.dart`)

**改动**:
- 删除自定义状态聚合，改为从 `DshSessionState` 读取
- 不再自己推断状态

**保留**:
- 控制台 UI 骨架
- 设备卡片
- 会话列表

#### ChatScreen (`lib/screens/chat_screen.dart`)

**改动**:
- 删除自维护状态，改为从 `DshSessionState` 读取
- 所有状态都通过 `DshSessionState` 访问

**保留**:
- 聊天 UI 骨架
- 会话侧栏
- 消息列表
- 审批/提问 UI

### 5. 新增/重构 Widget

#### ConnectionStatus (`lib/widgets/connection_status.dart`)

- 显示连接状态指示器
- 从 `DshSessionState` 读取状态

#### ServerCard (`lib/widgets/server_card.dart`)

- 显示服务器信息和状态
- 从 `DshSessionState` 读取状态

#### ConsoleDevices (`lib/widgets/console_devices.dart`)

- 重构为显示所有服务器的运行状态
- 从 `ServerManager` 读取数据

#### ConsoleMergedTile (`lib/widgets/console_merged_tile.dart`)

- 重构为按状态分组显示会话
- 从 `ServerManager` 读取数据

#### ConsoleAnimations (`lib/widgets/console_animations.dart`)

- 重构为更简洁的动画组件
- 保留 `ConsolePulseDot`, `ConsoleStatsCard`, `ConsoleEntrance`, `ConsoleEmptyState`

#### ToolStatusBar (`lib/widgets/tool_status_bar.dart`)

- 保持不变，显示当前正在执行的工具

## 文件改动清单

### 新增文件

| 文件 | 用途 |
|------|------|
| `lib/services/dsh_session_state.dart` | 状态中枢 |
| `lib/services/mux_event_dispatcher.dart` | 事件统一入口 |
| `lib/widgets/connection_status.dart` | 连接状态指示器 |
| `lib/widgets/server_card.dart` | 服务器卡片 |

### 重构文件

| 文件 | 改动 |
|------|------|
| `lib/services/chat_controller.dart` | 删除自维护状态，改为从中枢读取 |
| `lib/services/mux_stream.dart` | 删除自维护状态，改为通过回调分发事件 |
| `lib/services/session_monitor.dart` | 删除轮询推断，改为只做会话列表刷新 |
| `lib/services/server_manager.dart` | 删除二次聚合，改为只做服务器管理 |
| `lib/screens/console_screen.dart` | 删除自定义状态聚合，改为从中枢读取 |
| `lib/screens/chat_screen.dart` | 删除自维护状态，改为从中枢读取 |
| `lib/widgets/console_devices.dart` | 重构为显示所有服务器的运行状态 |
| `lib/widgets/console_merged_tile.dart` | 重构为按状态分组显示会话 |
| `lib/widgets/console_animations.dart` | 重构为更简洁的动画组件 |
| `lib/widgets/tool_status_bar.dart` | 保持不变 |

### 保留文件

| 文件 | 说明 |
|------|------|
| `lib/services/dsh_api.dart` | RPC 通信，保留 |
| `lib/services/dsh_auth.dart` | 鉴权，保留 |
| `lib/services/settings_service.dart` | 设置，保留 |
| `lib/services/sound_service.dart` | 提示音，保留 |
| `lib/services/notification_service.dart` | 通知，保留 |
| `lib/screens/settings_screen.dart` | 设置页，保留 |
| `lib/widgets/message_bubble.dart` | 消息气泡，保留 |
| `lib/widgets/session_drawer.dart` | 会话侧栏，保留 |
| `lib/widgets/changes_drawer.dart` | 变更抽屉，保留 |
| `lib/widgets/chat_input_bar.dart` | 输入栏，保留 |
| `lib/widgets/question_sheet.dart` | 提问表单，保留 |
| `lib/widgets/approval_card.dart` | 审批卡片，保留 |

## 预期效果

### 解决的问题

1. **状态不同步**: 所有状态都从 `DshSessionState` 读取，不再有多个模块各自猜测
2. **交互体验不一致**: 所有 mux 事件都通过 `MuxEventDispatcher` 分发，行为统一
3. **多 DSH 实例管理**: `ServerManager` 只做服务器管理，不再推断状态

### 保留的优势

1. **多服务器支持**: 保留现有的多服务器管理
2. **原生体验**: 保留现有的 UI 骨架和控件
3. **局域网直连**: 保留现有的 WebSocket 连接
4. **审批/提问**: 保留现有的审批和提问处理
5. **提示音/通知**: 保留现有的提示音和通知

## 后续优化建议

1. **拆分 ChatController**: 可以进一步拆分为更小的模块
2. **优化控制台 UI**: 可以添加更多统计和可视化
3. **添加更多服务器管理功能**: 如服务器分组、标签等
4. **优化重连逻辑**: 可以添加更智能的重连策略

## 验证方式

1. 启动 DSH Desktop，开启局域网访问
2. 启动 `dsh_tablet_client`，连接到 DSH
3. 在桌面端发起任务，观察 app 状态是否同步
4. 在 app 中审批/提问，观察桌面端是否响应
5. 断开网络，观察重连后状态是否恢复

## 总结

这次改造把 `dsh_tablet_client` 从"多个模块各自猜测状态"改为"单一权威状态源"，解决了状态不同步问题。改造保留了现有的功能骨架，只修改了状态管理方式，预计工作量约 200-300 行代码改动。