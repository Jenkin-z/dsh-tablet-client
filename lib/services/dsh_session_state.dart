import 'package:flutter/foundation.dart';
import '../models/connection_health.dart';
import '../models/pending.dart';
import 'changes_tracker.dart';
import 'model_service.dart';

/// 状态中枢：所有关键状态都从这里读取
///
/// 任何模块不能自己猜状态，只能从这个中枢读。
/// 所有 mux 事件都必须先进 MuxEventDispatcher，再更新这个中枢。
class DshSessionState extends ChangeNotifier {
  /// 供外部（如 MuxEventDispatcher）在批量更新后统一广播一次
  void notify() => notifyListeners();

  // ── 连接状态 ────────────────────────────────────

  bool _connected = false;
  bool _connecting = false;
  String? _connectionError;

  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get connectionError => _connectionError;

  void setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    notifyListeners();
  }

  void setConnecting(bool value) {
    if (_connecting == value) return;
    _connecting = value;
    notifyListeners();
  }

  void setConnectionError(String? value) {
    if (_connectionError == value) return;
    _connectionError = value;
    notifyListeners();
  }

  // ── 数据健康度 ──────────────────────────────────
  //
  // 绿色的含义必须诚实：它不能只代表「WebSocket 还在」。
  // 会话列表是 HTTP 拉的，socket 通、列表却失败是完全可能的
  // （历史上就发生过：session/list 参数名写错 → 列表空 → 设备全离线，
  //  而右上角一直是绿的）。所以这里单独记一次列表拉取的结果。

  bool? _sessionsOk;
  String? _sessionsError;

  /// null = 还没拉过；true = 最近一次成功；false = 最近一次失败
  bool? get sessionsOk => _sessionsOk;
  String? get sessionsError => _sessionsError;

  void setSessionsHealth({required bool ok, String? error}) {
    if (_sessionsOk == ok && _sessionsError == error) return;
    _sessionsOk = ok;
    _sessionsError = ok ? null : error;
    notifyListeners();
  }

  /// 降级：socket 通着，但数据侧已经不可信（列表拉不到）
  bool get degraded => _connected && _sessionsOk == false;

  /// 指示器该显示的健康状态（供 ConnectionStatus 使用）
  ///
  /// `_sessionsOk` 是三态：`null` = **还没验证过**，`true` = 验证过且成功，
  /// `false` = 验证过但失败。
  ///
  /// 曾经的写法是 `if (_sessionsOk == false) degraded else healthy`，
  /// 把 `null` 也算成健康 —— 于是 socket 一连上、第一次列表还没回来
  /// （以及每次 reset() 之后）就显示绿色，用户看到的就是「一直绿」。
  /// 「没验证过」只能算「连接中」，不能算「健康」。
  ConnectionHealth get health {
    if (_connecting) return ConnectionHealth.connecting;
    if (!_connected) return ConnectionHealth.offline;
    if (_sessionsOk == null) return ConnectionHealth.connecting;
    if (_sessionsOk == false) return ConnectionHealth.degraded;
    return ConnectionHealth.healthy;
  }

  // ── 会话状态 ────────────────────────────────────

  String? _sessionId;
  String _sessionTitle = 'DSH Agent';
  bool _agentRunning = false;
  bool _assistantStreaming = false;
  DateTime? _lastTurnEnd;
  DateTime? _lastActivity;

  String? get sessionId => _sessionId;
  String get sessionTitle => _sessionTitle;
  bool get agentRunning => _agentRunning;
  bool get assistantStreaming => _assistantStreaming;
  DateTime? get lastTurnEnd => _lastTurnEnd;
  DateTime? get lastActivity => _lastActivity;

  void setSessionId(String? value) {
    if (_sessionId == value) return;
    _sessionId = value;
    notifyListeners();
  }

  void setSessionTitle(String value) {
    if (_sessionTitle == value) return;
    _sessionTitle = value;
    notifyListeners();
  }

  // ── 当前模型 ────────────────────────────────────
  //
  // 权威来源是控制流的 `modelSelection` 投影（{lastUsed, next}），
  // 切换后 Host 会推新投影，这里只是缓存最近一次已知值。

  ModelSelection? _modelSelection;
  ModelSelection? get modelSelection => _modelSelection;

  void setModelSelection(ModelSelection? value) {
    if (_sameSelection(value, _modelSelection)) return;
    _modelSelection = value;
    notifyListeners();
  }

  static bool _sameSelection(ModelSelection? a, ModelSelection? b) {
    if (a == null || b == null) return a == b;
    return a.sameAs(b);
  }

  void setAgentRunning(bool value) {
    if (_agentRunning == value) return;
    _agentRunning = value;
    _lastActivity = DateTime.now();
    notifyListeners();
  }

  void setAssistantStreaming(bool value) {
    if (_assistantStreaming == value) return;
    _assistantStreaming = value;
    _lastActivity = DateTime.now();
    notifyListeners();
  }

  void setLastTurnEnd(DateTime? value) {
    _lastTurnEnd = value;
    _lastActivity = DateTime.now();
    notifyListeners();
  }

  // ── 审批/提问 ────────────────────────────────────
  //
  // Web 端语义（见 DSH_APPROVAL_QUESTIONS_PORTING_SPEC.md）：
  // · 每个会话各持有自己的待办，**不同会话的请求互不覆盖**
  // · 界面同一时刻只展示「当前会话」的那一个
  // · 同一会话内按优先级选举：plan-review > question > approval
  // · 落选者不丢弃，等获胜者消解后重新浮出

  final List<PendingApproval> _approvals = [];
  final List<PendingQuestion> _questions = [];
  bool _questionDialogOpen = false;

  List<PendingApproval> get approvals => List.unmodifiable(_approvals);

  /// 全部待回答问题（含其它会话）
  List<PendingQuestion> get allQuestions => List.unmodifiable(_questions);

  /// 当前会话待回答的问题（按优先级选举）
  PendingQuestion? get question {
    final sid = _sessionId;
    PendingQuestion? best;
    for (final q in _questions) {
      if (q.sessionId != sid) continue;
      if (best == null || _questionPriority(q) > _questionPriority(best)) {
        best = q;
      }
    }
    return best;
  }

  /// 其它会话是否有待处理的提问（用于侧栏提示）
  bool get hasForeignQuestion {
    final sid = _sessionId;
    return _questions.any((q) => q.sessionId != sid);
  }

  bool get questionDialogOpen => _questionDialogOpen;

  /// plan-review 优先于普通提问
  int _questionPriority(PendingQuestion q) => q.isPlanReview ? 1 : 0;

  void addApproval(PendingApproval approval) {
    // 同 approvalId 只保留一份
    if (_approvals.any((a) => a.approvalId == approval.approvalId)) return;
    _approvals.add(approval);
    notifyListeners();
  }

  void removeApproval(String approvalId) {
    final before = _approvals.length;
    _approvals.removeWhere((a) => a.approvalId == approvalId);
    if (_approvals.length != before) notifyListeners();
  }

  void clearApprovals() {
    if (_approvals.isEmpty) return;
    _approvals.clear();
    notifyListeners();
  }

  void addQuestion(PendingQuestion value) {
    // 同 rpcId 只保留一份
    if (_questions.any((q) => q.rpcId == value.rpcId)) return;
    _questions.add(value);
    notifyListeners();
  }

  void removeQuestion(String rpcId) {
    final before = _questions.length;
    _questions.removeWhere((q) => q.rpcId == rpcId);
    if (_questions.length != before) notifyListeners();
  }

  void setQuestionDialogOpen(bool value) {
    if (_questionDialogOpen == value) return;
    _questionDialogOpen = value;
    notifyListeners();
  }

  // ── 工具 ────────────────────────────────────────

  String? _activeTool;
  final ChangesTracker _changes = ChangesTracker();

  String? get activeTool => _activeTool;
  ChangesTracker get changes => _changes;

  void setActiveTool(String? value) {
    if (_activeTool == value) return;
    _activeTool = value;
    notifyListeners();
  }

  void applyToolView({
    required List<Map<String, String?>> diffs,
    required String title,
    required bool done,
    int? turn,
  }) {
    _changes.applyView(diffs: diffs, title: title, done: done, turn: turn);
    notifyListeners();
  }

  void clearChanges() {
    if (_changes.items.isEmpty) return;
    _changes.clear();
    notifyListeners();
  }

  // ── 会话列表 ────────────────────────────────────

  List<Map<String, dynamic>> _sessions = [];
  bool _loadingSessions = false;
  Set<String> _archivedIds = {};

  List<Map<String, dynamic>> get sessions => List.unmodifiable(_sessions);
  bool get loadingSessions => _loadingSessions;
  Set<String> get archivedIds => Set.unmodifiable(_archivedIds);

  void setSessions(List<Map<String, dynamic>> value) {
    _sessions = value;
    notifyListeners();
  }

  void setLoadingSessions(bool value) {
    if (_loadingSessions == value) return;
    _loadingSessions = value;
    notifyListeners();
  }

  void setArchivedIds(Set<String> value) {
    _archivedIds = value;
    notifyListeners();
  }

  /// 过滤归档会话后的可见列表
  List<Map<String, dynamic>> get visibleSessions {
    if (_archivedIds.isEmpty) return _sessions;
    return _sessions
        .where((s) => !_archivedIds.contains(s['sessionId']))
        .toList();
  }

  // ── 重置 ────────────────────────────────────────

  void reset() {
    _connected = false;
    _connecting = false;
    _connectionError = null;
    _sessionsOk = null;
    _sessionsError = null;
    _sessionId = null;
    _sessionTitle = 'DSH Agent';
    _agentRunning = false;
    _assistantStreaming = false;
    _lastTurnEnd = null;
    _lastActivity = null;
    _approvals.clear();
    _questions.clear();
    _questionDialogOpen = false;
    _activeTool = null;
    _changes.clear();
    _sessions = [];
    _loadingSessions = false;
    _archivedIds = {};
    notifyListeners();
  }

  // ── 批量更新 ────────────────────────────────────

  /// 某会话待处理的交互类型，用于列表状态点。
  ///
  /// 优先级与 Web 端一致：计划待审 > 等待回答 > 等待审批，
  /// 且**高于 running** —— 有待办时不再显示「运行中」。
  String? pendingKindOf(String sessionId) {
    var hasQuestion = false;
    for (final q in _questions) {
      if (q.sessionId != sessionId) continue;
      if (q.isPlanReview) return 'plan-review';
      hasQuestion = true;
    }
    if (hasQuestion) return 'question';
    for (final a in _approvals) {
      if (a.sessionId == sessionId) return 'approval';
    }
    return null;
  }

  /// 存在任何待处理交互的会话集合
  Set<String> get pendingSessionIds {
    final ids = <String>{};
    for (final a in _approvals) {
      ids.add(a.sessionId);
    }
    for (final q in _questions) {
      ids.add(q.sessionId);
    }
    return ids;
  }

  void updateSessionStatus(String sessionId, bool running) {
    for (var i = 0; i < _sessions.length; i++) {
      if (_sessions[i]['sessionId'] == sessionId) {
        if (_sessions[i]['running'] != running) {
          _sessions[i]['running'] = running;
          notifyListeners();
        }
        break;
      }
    }
  }
}