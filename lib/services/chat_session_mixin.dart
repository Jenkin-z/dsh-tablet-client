part of 'chat_controller.dart';

/// 会话管理 mixin（由 ChatController 混入）
///
/// 职责：会话列表、标题提取、切换、新建。
mixin _ChatSessionMixin on ChangeNotifier {
  // ── 子类必须提供的状态 ──────────────────────────
  List<Map<String, dynamic>> get sessions;
  set sessions(List<Map<String, dynamic>> v);
  String get currentTitle;
  set currentTitle(String v);
  bool get loadingSessions;
  set loadingSessions(bool v);
  bool get connected;
  List<DshMessage> get messages;
  Set<String> get queuedTexts;
  Set<String> get _pendingEchoRpc;
  /// 清掉「刚发出」标记（回声已到 / 切会话）
  void clearSentEcho();
  bool get agentRunning;
  set agentRunning(bool v);
  String? get activeTool;
  set activeTool(String? v);
  ChangesTracker get changes;
  SettingsService get settings;
  DshApi? get _api;
  String? get _muxSessionId;

  // ── 依赖方法 ────────────────────────────────────
  void connectMux(String sessionId);
  void Function(String message)? get onShowSnackBar;
  VoidCallback? get onShowQuestionDialog;

  // ── 会话标题 ────────────────────────────────────

  String titleFor(String? sessionId) {
    if (sessionId == null) return 'DSH Agent';
    for (final s in sessions) {
      if (s['sessionId'] == sessionId) {
        final proj = s['projections'] as Map<String, dynamic>?;
        final values = proj?['values'] as Map<String, dynamic>?;
        final t = values?['title'];
        if (t is String && t.isNotEmpty) return t;
        if (t is Map<String, dynamic>) {
          final inner = t['title'];
          if (inner is String && inner.isNotEmpty) return inner;
        }
        if (s['blank'] == true) return '新会话';
        final id = s['sessionId'] as String? ?? '';
        return id.length > 8
            ? '会话 …${id.substring(id.length - 6)}'
            : '未命名会话';
      }
    }
    return 'DSH Agent';
  }

  // ── 会话列表 ────────────────────────────────────

  Future<void> refreshSessions() async {
    if (_api == null) return;
    loadingSessions = true;
    notifyListeners();
    try {
      final items = await _api!.listSessions();
      sessions = items;
      currentTitle = titleFor(settings.sessionId);
    } catch (_) {
      // 静默失败
    } finally {
      loadingSessions = false;
      notifyListeners();
    }
  }

  // ── 切换会话 ────────────────────────────────────

  Future<void> switchSession(String sessionId) async {
    if (sessionId == _muxSessionId && connected) return;
    await settings.setSessionId(sessionId);
    try {
      final session =
          sessions.firstWhere((s) => s['sessionId'] == sessionId);
      final cwd = session['cwd'] as String? ?? '';
      if (cwd.isNotEmpty) {
        await settings.setWsExpanded(cwd, true);
      }
    } on StateError {
      // session not in local list yet
    }
    final srv = settings.active;
    if (srv != null) {
      await settings.markSeen(settings.seenKey(srv.id, sessionId));
    }
    messages.clear();
    activeTool = null;
    agentRunning = false;
    currentTitle = titleFor(sessionId);
    _pendingEchoRpc.clear();
    queuedTexts.clear();
    clearSentEcho();
    changes.clear();
    notifyListeners();
    connectMux(sessionId);
    onShowQuestionDialog?.call();
  }

  // ── 新建会话 ────────────────────────────────────

  Future<void> createNewSession({String? cwd}) async {
    if (_api == null || !connected) return;
    try {
      final id = await _api!.createSession(cwd: cwd);
      await refreshSessions();
      await switchSession(id);
    } catch (e) {
      onShowSnackBar?.call('新建会话失败: $e');
    }
  }
}
