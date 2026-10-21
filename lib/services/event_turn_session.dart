part of 'event_dispatcher.dart';

// ── session 状态 / tool / turn 生命周期 / 投影（event_turn_session.dart）──
//
// 只搬代码不改逻辑：
// - `running: true` 必须受 [_turnClosed] 约束（收尾语义，勿动）；
// - tool/call 的参数是未解析 JSON 字符串，摘要见 model_catalog；
// - journal 事件名（turn/start、turn/end、tool/call 等）见 docs/MUX_PROTOCOL.md；
// mixin 依赖字段声明在 [_EventDispatcherCore]（event_dispatcher.dart）。

mixin EventDispatcherTurnSession on _EventDispatcherCore {
  void onToolCall(String toolName, [String? arguments]) {
    _touchActivity();
    // 参数是未解析的 JSON 字符串，抽一个能看懂的摘要放进状态栏
    state.setActiveTool(_toolSummary(toolName, arguments));
    state.setAgentRunning(true);
  }

  /// 从工具参数里抽一行摘要（命令 / 路径）
  String _toolSummary(String toolName, String? rawArguments) {
    final detail = extractToolDetail(rawArguments);
    return detail == null || detail.isEmpty ? toolName : '$toolName · $detail';
  }

  void onToolResult() {
    state.setActiveTool(null);
  }

  /// `api-session/status` / control 流的运行状态推送
  ///
  /// 写入权威中枢，并顺带修正当前会话的 agentRunning，
  /// 避免轮询（8s）造成的状态滞后。
  ///
  /// **`running: true` 必须受 [_turnClosed] 约束。** 这条通道是
  /// `$events` 的 emit，重连时 Host 会把当前状态重放一遍；如果本轮的
  /// `turn/end` 已经处理过（`_turnClosed == true`），此时再来的
  /// `running: true` 是**上一轮的残留**，不是新一轮 —— 真正的新一轮会先发
  /// `turn/start`，那时 [_turnClosed] 已被清掉。
  ///
  /// 不设这道闸，重连一次就会把已收尾的会话顶成「进行中」，
  /// 而且之后不会再有 `turn/end` 来收尾，按钮就永久卡住。
  void onSessionStatus(String sessionId, bool running) {
    state.updateSessionStatus(sessionId, running);
    if (sessionId == state.sessionId) {
      if (!running || !_turnClosed) {
        state.setAgentRunning(running);
      }
    }
    onSessionStatusExternal?.call(sessionId, running);
  }

  void onToolView(ToolViewRecord rec) {
    _touchActivity();
    state.applyToolView(
      diffs: rec.diffs,
      title: rec.title,
      done: rec.done,
      turn: rec.turn,
    );
  }

  /// 新一轮开始：重新武装运行态
  ///
  /// `turn/end` 会把运行态置空闲，但排队消息会让同一轮继续。
  /// Host 的 `api-session/status` 只在**状态变化**时推送，所以不能依赖它
  /// 把 running 从 false 拉回 true —— 这里用 journal 的 `turn/start` 兜底。
  void onTurnStart() {
    _touchActivity();
    _turnClosed = false;
    state.setAgentRunning(true);
    state.notify();
  }

  void onTurnEnd() {
    _turnClosed = true;
    // 只清当前会话的待办：别的会话的审批/提问不该被本轮结束牵连
    final sid = state.sessionId;
    for (final a in state.approvals.where((a) => a.sessionId == sid).toList()) {
      state.removeApproval(a.approvalId);
    }
    for (final q in state.allQuestions.where((q) => q.sessionId == sid).toList()) {
      state.removeQuestion(q.rpcId);
    }
    if (state.questionDialogOpen) {
      state.setQuestionDialogOpen(false);
      onPopQuestionDialog?.call();
    }
    state.setAgentRunning(false);
    state.setAssistantStreaming(false);
    state.setActiveTool(null);
    state.setLastTurnEnd(DateTime.now());

    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(isStreaming: false);
    }
    state.notify();
  }

  void onQueueUpdate(List<Map<String, dynamic>> queueItems) {
    // 队列更新，暂不处理
  }

  void onWorkspaceBaseline(List<String> archivedSessionIds) {
    state.setArchivedIds(Set.from(archivedSessionIds));
  }

  void onControlBaseline(Map<String, dynamic> baseline) {
    // 控制基线，暂不处理
  }

  void onProjectionChange(String sessionId, String key, dynamic value) {
    // 只关心当前会话的模型选择投影，其余投影暂不消费
    if (key != 'modelSelection') return;
    if (sessionId != state.sessionId) return;
    state.setModelSelection(ModelSelection.fromProjection(value));
  }

  /// 开窗快照里的投影（`{values: {...}}`）
  ///
  /// 重连后靠它恢复当前模型；不处理的话切换过模型也会显示成默认值。
  void applySnapshotProjections(Map<String, dynamic> projections) {
    final values = projections['values'];
    if (values is! Map) return;
    final selection = ModelSelection.fromProjection(values['modelSelection']);
    if (selection != null) state.setModelSelection(selection);
  }
}
