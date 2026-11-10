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
    if (!_turnClosed) {
      // 工具调用前的 assistant 文本是过程内容：固化为步骤条目
      // （Web 端折叠进过程区的做法），不再直接丢弃。
      addProcessStep(toolName, arguments);
    } else {
      _clearDelta();
    }
    // 结束打字机态 + 工具摘要上状态栏 + 置 running（supervisor 一次提交）
    supervisor.toolCall(_toolSummary(toolName, arguments));
  }

  /// 从工具参数里抽一行摘要（命令 / 路径）
  String _toolSummary(String toolName, String? rawArguments) {
    final detail = extractToolDetail(rawArguments);
    return detail == null || detail.isEmpty ? toolName : '$toolName · $detail';
  }

  void onToolResult(bool failed) {
    supervisor.toolResult();
    completeProcessTool(failed);
  }

  /// 会话级错误上屏（DSH turn/end reason.kind=error、api-session/error；
  /// opencode session.execution.failed）
  ///
  /// 模型/Provider 报错时 Host 只把运行态收掉，消息流里什么都不留，
  /// 用户看到的就是「对话中断了却不显示任何东西」。这里把错误落成
  /// system 气泡（MessageBubble 的红色居中样式），中断必须有据可查。
  ///
  /// 调用方必须在 onTurnEnd **之前**触发（DSH 的 mux 分发已是这个顺序）：
  /// turn 收尾后 [_turnClosed] 置位，重连重放的同一条错误就不会再上屏。
  void onSessionError(String sessionId, String message) {
    if (message.isEmpty) return;
    if (sessionId != state.sessionId) {
      // 非当前会话没有消息流可落（切走再切回也会被历史装载清掉），
      // 退而求其次给一条全局提示
      onShowSnackBar?.call('其他会话出错：$message');
      return;
    }
    if (_turnClosed) return;
    _clearDelta();
    _messages.add(ChatMessage(
      id: 'err-${DateTime.now().microsecondsSinceEpoch}',
      role: 'system',
      content: message,
    ));
    _bumpMessages();
    onScrollToBottom?.call();
  }

  /// `api-session/status` / control 流的运行状态推送
  ///
  /// 写入权威中枢（会话列表视图），当前会话的运行态迁移则交给
  /// supervisor 的权威命令：
  /// - `running:true` 受 turnClosed 闸门约束 —— 这条通道是 `$events`
  ///   的 emit，重连时 Host 会把当前状态重放一遍；本轮 turn/end 已处理过
  ///   （turnClosed）时，再来的 running:true 是上一轮的残留，不是新一轮
  ///   （真正的新一轮会先发 turn/start，那时闸门已重新武装）。不设这道闸，
  ///   重连一次就会把已收尾的会话顶成「进行中」且再无 turn/end 来收尾。
  /// - `running:false` 永远接受：失败路径事件全丢时（opencode 中途挂掉
  ///   实测不发 tool.failed / execution.failed），5s 轮询到这里自愈，
  ///   工具条/打字机态一并收掉。
  void onSessionStatus(String sessionId, bool running) {
    state.updateSessionStatus(sessionId, running);
    if (sessionId == state.sessionId) {
      supervisor.authorityRunning(running);
    }
    onSessionStatusExternal?.call(sessionId, running);
  }

  void onToolView(ToolViewRecord rec) {
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
  /// 把 busy 从空闲拉回来 —— 这里用 journal 的 `turn/start` 兜底。
  /// 队列非空时 turn/end 落的是 queued 相位，turn/start 到这里转 running。
  void onTurnStart() {
    // 先重新武装：resetProcess 的 turnClosed 检查才能看到新轮次
    supervisor.turnStart();
    _clearDelta();
    // 新 turn 的 assistant 气泡必须重新建；上一轮最终回答保留在历史里。
    _currentAssistantId = null;
    // 上一轮的过程步骤卡随之退场（收起卡只服务当前轮）
    resetProcess();
  }

  void onTurnEnd() {
    // turnClosed=true + idle/queued（队列非空）+ 收打字机/工具条，
    // supervisor 一次事务提交，UI 不见中间帧
    supervisor.turnEnd();
    _clearDelta();
    // 过程步骤卡收起（条目保留，可展开回看）
    collapseProcess();
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
    state.setLastTurnEnd(DateTime.now());

    var idx = _currentAssistantId == null
        ? -1
        : _messages.indexWhere((m) => m.id == _currentAssistantId);
    if (idx < 0) idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(isStreaming: false);
    }
    _bumpMessages();
  }

  /// stale-busy 自愈（与后端无关的兜底，供重连/历史装载后调用）
  ///
  /// 「只清不设」：仅当消息流尾部表明最后一轮确实已收尾
  /// （见 [isSessionActuallyIdle]）才清掉运行态；判定不了就什么都不做。
  /// 真在跑的会话由各自的权威通道恢复（opencode 的 active 轮询 /
  /// DSH 的 control 推送），本方法永远不会把它们顶成「进行中」。
  ///
  /// DSH 的重连不接这条：journal 重放会补发 turn/end，control 推送
  /// 受 turnClosed 闸门约束，已有权威自愈路径。
  void clearStaleBusyIfIdle(String sessionId) {
    if (sessionId.isEmpty || sessionId != state.sessionId) return;
    if (!isSessionActuallyIdle(_messages)) return;
    supervisor.settleToIdle();
    state.updateSessionStatus(sessionId, false);
  }

  void onWorkspaceBaseline(List<String> archivedSessionIds) {
    state.setArchivedIds(Set.from(archivedSessionIds));
  }

  // onControlBaseline 的队列消费在 event_queue.dart（本分片不管队列）

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
