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
  String? get _lastSentText;
  set _lastSentText(String? v);
  DateTime? get _lastSentAt;
  set _lastSentAt(DateTime? v);
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
      messages[idx] = messages[idx].copyWith(content: text);
    } else {
      messages.add(DshMessage(
        id: 'a-${_uuid.v4()}',
        role: 'assistant',
        content: text,
      ));
    }
    notifyListeners();
    onScrollToBottom?.call();
  }

  // ── 用户消息 ────────────────────────────────────

  void onUserMessage(String text, String? rpcId, String seq) {
    final key = 'u$seq';
    if (seq.isNotEmpty && !_seenUserSeq.add(key)) return;
    if (rpcId != null && _pendingEchoRpc.remove(rpcId)) return;
    if (_lastSentText == text &&
        _lastSentAt != null &&
        DateTime.now().difference(_lastSentAt!) < const Duration(seconds: 60)) {
      _lastSentText = null;
      return;
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
    agentRunning = false;
    activeTool = null;
    approvals.clear();
    question = null;
    if (questionDialogOpen) {
      questionDialogOpen = false;
      onPopQuestionDialog?.call();
    }
    final idx = messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      messages[idx] = messages[idx].copyWith(isStreaming: false);
    }
    notifyListeners();
    if (settings.soundEnabled && settings.completionSound) {
      SoundService.done(customPath: settings.customSoundPath('done'));
    }
    refreshSessions();
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
    final removed = queuedTexts.difference(currentQueued);
    queuedTexts
      ..clear()
      ..addAll(currentQueued);
    if (removed.isEmpty) return;
    messages.removeWhere(
        (m) => m.role == 'user' && removed.contains(m.content));
    notifyListeners();
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
    final running = current?['running'] == true;
    if (_wasCurrentRunning && !running) {
      agentRunning = false;
      activeTool = null;
      final idx = messages.indexWhere((m) => m.isStreaming);
      if (idx >= 0) {
        messages[idx] = messages[idx].copyWith(isStreaming: false);
      }
      notifyListeners();
    }
    _wasCurrentRunning = running;
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
