part of 'chat_controller.dart';

/// 消息流处理 mixin（由 ChatController 混入）
///
/// 职责：mux 快照、流式增量、助手消息、用户消息、工具视图、turn 生命周期、队列同步。
mixin _ChatMessageMixin on ChangeNotifier {
  // ── 子类必须提供的状态 ──────────────────────────
  List<DshMessage> get messages;
  ChangesTracker get changes;
  Set<String> get queuedTexts;
  Set<String> get _seenUserSeq;
  Set<String> get _pendingEchoRpc;
  bool get agentRunning;
  set agentRunning(bool v);
  String? get activeTool;
  set activeTool(String? v);
  bool get connected;
  StringBuffer get _deltaBuffer;
  Timer? get _deltaFlushTimer;
  set _deltaFlushTimer(Timer? t);
  Uuid get _uuid;
  SettingsService get settings;
  List<Map<String, dynamic>> get sessions;

  // ── UI 回调 ────────────────────────────────────
  VoidCallback? get onScrollToBottom;
  VoidCallback? get onJumpToLatest;

  // ── 依赖方法（由 ChatController 实现） ──────────
  void _touchActivity();
  Future<void> refreshSessions();

  /// 该文本是否是我们刚发出、还没被回声确认的那条
  bool matchesLastSentEcho(String text);

  /// 清掉「刚发出」标记（切换会话 / 回声已到）
  void clearSentEcho();

  // ── 快照 ────────────────────────────────────────

  void onMuxSnapshot(List<Map<String, dynamic>> records) {
    final parsed = parseHistory(records);
    for (final m in parsed) {
      if (m.role == 'user' && m.id.startsWith('u')) {
        _seenUserSeq.add(m.id);
      }
    }
    messages.clear();
    _seenUserSeq.clear();
    for (final p in parsed) {
      messages.add(DshMessage(id: p.id, role: p.role, content: p.text));
      _seenUserSeq.add(p.id);
    }
    changes.clear();
    for (final v in parseHistoryViews(records)) {
      changes.applyView(
          diffs: v.diffs, title: v.title, done: v.done, turn: v.turn);
    }
    notifyListeners();
    onJumpToLatest?.call();
  }

  // ── 流式增量 ────────────────────────────────────

  void onDelta(String delta) {
    _touchActivity();
    _deltaBuffer.write(delta);
    _deltaFlushTimer ??= Timer(const Duration(milliseconds: 120), flushDelta);
  }

  void flushDelta() {
    _deltaFlushTimer = null;
    final text = _deltaBuffer.toString();
    _deltaBuffer.clear();
    if (text.isEmpty) return;
    final idx = messages.indexWhere((m) => m.isStreaming);
    if (idx < 0 && !agentRunning) return;
    agentRunning = true;
    if (idx >= 0) {
      messages[idx] = messages[idx].copyWith(
        content: messages[idx].content + text,
      );
    } else {
      activeTool = null;
      messages.add(DshMessage(
        id: 'stream-${_uuid.v4()}',
        role: 'assistant',
        content: text,
        isStreaming: true,
      ));
    }
    notifyListeners();
    onScrollToBottom?.call();
  }

  // ── 助手消息 ────────────────────────────────────

  void onAssistantFinal(String text) {
    _touchActivity();
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _deltaBuffer.clear();
    activeTool = null;
    final idx = messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      messages[idx] = messages[idx].copyWith(content: text, isStreaming: false);
    } else {
      final lastAssistant = messages.lastIndexWhere((m) => m.role == 'assistant');
      final existing = lastAssistant >= 0 ? messages[lastAssistant].content : '';
      if (lastAssistant >= 0 &&
          (existing == text ||
              (existing.isNotEmpty && text.startsWith(existing)))) {
        messages[lastAssistant] =
            messages[lastAssistant].copyWith(content: text, isStreaming: false);
      } else {
        messages.add(DshMessage(
          id: 'a-${_uuid.v4()}',
          role: 'assistant',
          content: text,
        ));
      }
    }
    notifyListeners();
    onScrollToBottom?.call();
  }

  // ── 用户消息 ────────────────────────────────────

  void onUserMessage(String text, String? rpcId, String seq) {
    final key = 'u$seq';
    if (seq.isNotEmpty && !_seenUserSeq.add(key)) return;
    // 乐观气泡已在列表里：回声只补上服务端 id，不能再跳过导致气泡被队列更新删掉后无法回来。
    if (rpcId != null && _pendingEchoRpc.remove(rpcId)) {
      final idx = messages.lastIndexWhere((m) => m.id == 'echo-$rpcId');
      if (idx >= 0) {
        messages[idx] = messages[idx].copyWith(id: key.isEmpty ? messages[idx].id : key);
        notifyListeners();
      }
      return;
    }
    if (matchesLastSentEcho(text)) {
      clearSentEcho();
      final idx = messages.lastIndexWhere(
        (m) => m.role == 'user' && (m.id.startsWith('u-') || m.id.startsWith('echo-')),
      );
      if (idx >= 0 && messages[idx].content == text) {
        messages[idx] = messages[idx].copyWith(id: key.isEmpty ? messages[idx].id : key);
        notifyListeners();
        return;
      }
    }
    // 内容去重：如果最后一条用户消息内容相同，跳过回声
    if (messages.isNotEmpty &&
        messages.last.role == 'user' &&
        messages.last.content == text) {
      return;
    }
    _touchActivity();
    messages.add(DshMessage(
      id: key.isEmpty ? 'u-${_uuid.v4()}' : key,
      role: 'user',
      content: text,
    ));
    notifyListeners();
    onScrollToBottom?.call();
  }

  // ── 工具视图 ────────────────────────────────────

  void onToolView(ToolViewRecord v) {
    _touchActivity();
    changes.applyView(
        diffs: v.diffs, title: v.title, done: v.done, turn: v.turn);
    notifyListeners();
  }

  void clearToolStatus() {
    if (activeTool == null) return;
    activeTool = null;
    notifyListeners();
  }

  // ── Turn 生命周期 ───────────────────────────────

  void onTurnEnd() {
    approvals.clear();
    question = null;
    if (questionDialogOpen) {
      questionDialogOpen = false;
      onPopQuestionDialog?.call();
    }
    // turn/end 只代表「本轮」结束：Agent 仍在运行时不能标记为已完成，
    // 否则会出现 PC 还在跑、APP 已显示完成（多轮任务/子任务场景）。
    if (_wasCurrentRunning) {
      activeTool = null;
      final idx = messages.indexWhere((m) => m.isStreaming);
      if (idx >= 0) {
        messages[idx] = messages[idx].copyWith(isStreaming: false);
      }
      notifyListeners();
    } else {
      finishRunning();
    }
    refreshSessions();
  }

  // ── 实时运行状态（api-session/status） ──────────

  /// Host 实时推送的 Agent 运行状态：同时驱动监控台与聊天状态
  void onSessionStatus(String sessionId, bool running) {
    final srv = settings.active;
    if (srv != null) manager?.applySessionStatus(srv.id, sessionId, running);
    if (sessionId != settings.sessionId) return;
    _wasCurrentRunning = running;
    if (running) {
      if (!agentRunning) {
        agentRunning = true;
        notifyListeners();
      }
      return;
    }
    finishRunning();
  }

  /// Agent 转为空闲：收尾流式消息与工具状态，并按需提示完成
  void finishRunning() {
    final wasRunning = agentRunning;
    agentRunning = false;
    activeTool = null;
    final idx = messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      messages[idx] = messages[idx].copyWith(isStreaming: false);
    }
    notifyListeners();
    if (wasRunning && settings.soundEnabled && settings.completionSound) {
      SoundService.done(customPath: settings.customSoundPath('done'));
    }
  }

  // ── 队列同步 ────────────────────────────────────

  void onQueueUpdate(List<Map<String, dynamic>> items) {
    final currentQueued = <String>{};
    for (final item in items) {
      final msg = item['message'] as Map<String, dynamic>?;
      if (msg == null) continue;
      final content = msg['content'] as List<dynamic>? ?? [];
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map<String, dynamic> && part['type'] == 'text') {
          buf.write(part['text'] as String? ?? '');
        }
      }
      if (buf.isNotEmpty) currentQueued.add(buf.toString());
    }
    // 出队只表示 Agent 已取走，不代表用户没说过。删气泡会和回声去重打架，消息会永久消失。
    queuedTexts
      ..clear()
      ..addAll(currentQueued);
  }

  // ── 监控台联动 ──────────────────────────────────

  void onMonitorTick() {
    final srv = settings.active;
    final id = settings.sessionId;
    if (srv == null || id == null) return;
    Map<String, dynamic>? current;
    for (final s in manager?.monitorOf(srv.id)?.sessions ?? const []) {
      if (s['sessionId'] == id) {
        current = s;
        break;
      }
    }
    // 会话尚未出现在轮询列表中（如刚新建）时状态未知，不能当作已结束
    if (current == null) return;
    final running = current['running'] == true;
    _wasCurrentRunning = running;
    if (running) {
      // 轮询兜底：APP 在任务进行中启动时可能已错过实时帧
      if (!agentRunning) {
        agentRunning = true;
        notifyListeners();
      }
      return;
    }
    if (agentRunning) finishRunning();
  }

  // ── 子类必须提供的字段 ──────────────────────────
  List<PendingApproval> get approvals;
  PendingQuestion? get question;
  set question(PendingQuestion? q);
  bool get questionDialogOpen;
  set questionDialogOpen(bool v);
  VoidCallback? get onPopQuestionDialog;
  ServerManager? get manager;
  bool get _wasCurrentRunning;
  set _wasCurrentRunning(bool v);
}
