import 'package:flutter/foundation.dart';
import '../models/connection_health.dart';
import '../models/pending.dart';
import 'changes_tracker.dart';
import 'model_catalog.dart';

part 'session_state_pending.dart';
part 'session_state_sessions.dart';

/// 库内共享宿主：声明状态中枢各分片（mixin）依赖的字段与方法，
/// 本身不对外暴露。[SessionState] 继承它并混入各职责分片。
///
/// 注意：分片用 `mixin X on _SessionStateCore` 挂载，**不能**写成
/// `on SessionState` —— 那会让 mixin 与宿主类互为超接口，
/// Dart 直接报 recursive_interface_inheritance。
abstract class _SessionStateCore extends ChangeNotifier {
  /// 供外部（如 EventDispatcher）在批量更新后统一广播一次
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
  //
  // 但**绝不能把轮询的结果也算进来**：ServerManager 每 8 秒对当前机器做一次
  // HTTP 轮询，它成功只说明「HTTP 能拉到列表」，与对话页那条 WebSocket 无关。
  // 曾经 main.dart 把 onActiveHealth 直接接到 setSessionsHealth，于是
  // 只要轮询活着，对话页顶部的点就恒绿 —— 哪怕 mux 早就断了。
  // 两个信号必须分开存，各归各的消费者。

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
}

/// 状态中枢（与后端无关）：所有关键状态都从这里读取
///
/// 任何模块不能自己猜状态，只能从这个中枢读。
/// 所有后端事件都必须先进 EventDispatcher，再更新这个中枢。
///
/// 按职责拆分（part 文件，同库共享私有作用域，对外 API 不变）：
/// - session_state_pending.dart：审批 / 提问 / 表单（按会话隔离 + 优先级选举）
/// - session_state_sessions.dart：工具视图 + 会话列表
class SessionState extends _SessionStateCore
    with SessionStatePending, SessionStateTools {
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
    _forms.clear();
    _formDialogOpen = false;
    _activeTool = null;
    _changes.clear();
    _sessions = [];
    _loadingSessions = false;
    _archivedIds = {};
    notifyListeners();
  }
}
