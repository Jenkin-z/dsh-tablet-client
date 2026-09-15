import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../widgets/approval_card.dart';
import '../widgets/question_sheet.dart';
import 'changes_tracker.dart';
import 'dsh_api.dart';
import 'dsh_auth.dart';
import 'mux_stream.dart';
import 'server_manager.dart';
import 'settings_service.dart';
import 'sound_service.dart';

part 'chat_approval_mixin.dart';
part 'chat_message_mixin.dart';
part 'chat_session_mixin.dart';

/// 聊天业务逻辑控制器：管理连接、消息、审批、会话切换
///
/// UI 层通过 addListener 监听变更，通过公开方法触发操作。
/// 依赖 Context 的操作（SnackBar、Dialog）通过回调委托给 UI。
///
/// - 审批/问题管理 → `chat_approval_mixin.dart`（part 文件）
/// - 消息流处理 → `chat_message_mixin.dart`（part 文件）
/// - 会话管理 → `chat_session_mixin.dart`（part 文件）
class ChatController extends ChangeNotifier
    with _ChatApprovalMixin, _ChatMessageMixin, _ChatSessionMixin {
  final SettingsService settings;
  final ServerManager? manager;

  // ── API / Stream ────────────────────────────────
  DshApi? _api;
  MuxStream? _mux;

  // ── 公开状态（UI 直接读） ───────────────────────
  final List<DshMessage> messages = [];
  List<Map<String, dynamic>> sessions = [];
  String currentTitle = 'DSH Agent';
  bool connecting = true;
  @override
  bool connected = false;
  /// mux 当前实际连接的会话 ID，与 settings.sessionId 独立。
  String? get muxSessionId => _muxSessionId;
  /// 过滤归档会话后的可见列表（供 SessionDrawer 使用）
  List<Map<String, dynamic>> get visibleSessions {
    final srv = settings.active;
    final archived = srv != null && manager != null
        ? manager!.monitorOf(srv.id)?.archivedIds
        : null;
    final archivedSet = archived ?? const <String>{};
    if (archivedSet.isEmpty) return sessions;
    return sessions
        .where((s) => !archivedSet.contains(s['sessionId']))
        .toList();
  }
  bool sending = false;
  bool agentRunning = false;
  bool loadingSessions = false;
  String? error;
  String? activeTool;
  final ChangesTracker changes = ChangesTracker();
  @override
  final List<PendingApproval> approvals = [];
  final Set<String> queuedTexts = {};
  @override
  PendingQuestion? question;
  @override
  bool questionDialogOpen = false;

  // ── 内部状态 ────────────────────────────────────
  /// mux 当前实际连接的会话 ID，与 settings.sessionId 独立。
  /// 用于 switchSession / router 判断是否需要真正切换。
  String? _muxSessionId;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final Set<String> _pendingEchoRpc = {};
  final Set<String> _seenUserSeq = {};
  String? _lastSentText;
  DateTime? _lastSentAt;
  bool _wasCurrentRunning = false;
  Timer? _approvalPollTimer;
  final _deltaBuffer = StringBuffer();
  Timer? _deltaFlushTimer;
  final _uuid = const Uuid();

  // ── UI 回调（依赖 Context 的操作委托给 UI 层） ──
  @override
  VoidCallback? onScrollToBottom;
  @override
  VoidCallback? onJumpToLatest;
  @override
  VoidCallback? onShowQuestionDialog;
  @override
  VoidCallback? onPopQuestionDialog;
  void Function(String message)? onShowSnackBar;

  ChatController({
    required this.settings,
    this.manager,
  });

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _deltaFlushTimer?.cancel();
    _approvalPollTimer?.cancel();
    _mux?.dispose();
    super.dispose();
  }

  // ── 初始化 / 重连 ───────────────────────────────

  Future<void> boot() async {
    connecting = true;
    error = null;
    notifyListeners();

    final srv = settings.active;
    if (srv == null) {
      connecting = false;
      connected = false;
      error = '还没有 PC，去设置里添加。';
      notifyListeners();
      return;
    }
    if (srv.unpaired) {
      connecting = false;
      connected = false;
      error = '「${srv.name}」授权已过期，去设置里重新授权。';
      notifyListeners();
      return;
    }
    _api = DshApi(baseUrl: srv.httpUrl, cookie: srv.cookie);

    try {
      final ok = await _api!.testConnection();
      if (!ok) {
        connecting = false;
        connected = false;
        error = '连接失败: ${srv.httpUrl}\n请检查 PC 端 DSH 是否启动、同一局域网。';
        notifyListeners();
        _scheduleReconnect();
        return;
      }
    } on DshAuthException catch (e) {
      if (e.unpaired) {
        await settings.patchServer(
          srv.id,
          (s) => s.copyWith(unpaired: true, lastError: e.message),
        );
      }
      connecting = false;
      connected = false;
      error = e.message;
      notifyListeners();
      return;
    }

    try {
      String? sessionId = settings.sessionId;
      if (sessionId != null) {
        final valid = await _validateSession(sessionId);
        if (!valid) sessionId = null;
      }
      sessionId ??= await _api!.createSession();
      await settings.setSessionId(sessionId);
      await settings.markSeen(settings.seenKey(srv.id, sessionId));
      await refreshSessions();
      connectMux(sessionId);
      connecting = false;
      connected = true;
      error = null;
      notifyListeners();
      _reconnectAttempts = 0;
      onJumpToLatest?.call();
    } catch (e) {
      connecting = false;
      connected = false;
      error = '初始化失败: $e';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<bool> _validateSession(String sessionId) async {
    try {
      await _api!.getHistory(sessionId, maxMessages: 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleReconnect() {
    if (!settings.autoReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(
        seconds: _reconnectAttempts > 5 ? 30 : _reconnectAttempts * 3);
    _reconnectTimer = Timer(delay, boot);
  }

  // ── 会话管理（实现在 chat_session_mixin.dart） ──

  // ── Mux 连接 ────────────────────────────────────

  void connectMux(String sessionId) {
    _mux?.dispose();
    _muxSessionId = sessionId;
    final mux = MuxStream(
      wsBaseUrl: settings.wsUrl,
      cookie: settings.active?.cookie,
    );
    mux.sessionId = sessionId;
    mux.onTextDelta = onDelta;                    // _ChatMessageMixin
    mux.onAssistantMessage = onAssistantFinal;    // _ChatMessageMixin
    mux.onUserMessage = onUserMessage;            // _ChatMessageMixin
    mux.onToolView = onToolView;                  // _ChatMessageMixin
    mux.onSnapshot = onMuxSnapshot;               // _ChatMessageMixin
    mux.onApproval = onApproval;                  // _ChatApprovalMixin
    mux.onApprovalResolved = onApprovalResolved;  // _ChatApprovalMixin
    mux.onQuestion = onQuestion;                  // _ChatApprovalMixin
    mux.onQuestionResolved = onQuestionResolved;  // _ChatApprovalMixin
    mux.onToolCall = (name) {
      activeTool = name;
      notifyListeners();
    };
    mux.onToolResult = clearToolStatus;           // _ChatMessageMixin
    mux.onTurnEnd = onTurnEnd;                    // _ChatMessageMixin
    mux.onQueueUpdate = onQueueUpdate;            // _ChatMessageMixin
    mux.onWorkspaceBaseline = (ids) {
      // 将 workspace/follow 推送的归档 ID 同步到对应 ServerMonitor
      final srv = settings.active;
      if (srv != null && manager != null) {
        final m = manager!.monitorOf(srv.id);
        if (m != null) {
          m.archivedIds = ids.toSet();
          manager!.notifyListeners();
        }
      }
    };
    mux.onDisconnected = () {
      connected = false;
      notifyListeners();
      _scheduleReconnect();
    };
    mux.connect();
    connected = true;
    notifyListeners();
    _mux = mux;
    _approvalPollTimer?.cancel();
    _approvalPollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _checkApprovalsStale());
  }

  // ── Mux 事件处理（实现在 chat_message_mixin.dart） ──

  void _checkApprovalsStale() {
    checkApprovalsStale(settings.sessionId, _mux?.lastCursor);
  }

  // ── 发送 / 取消 ─────────────────────────────────

  Future<String?> send(String text) async {
    if (text.isEmpty || sending || !connected) return null;
    final sessionId = settings.sessionId;
    if (sessionId == null) return null;

    sending = true;
    agentRunning = true;
    messages.add(DshMessage(
      id: 'u-${_uuid.v4()}',
      role: 'user',
      content: text,
    ));
    notifyListeners();

    try {
      final rpcId = await _api!.sendPrompt(sessionId, text);
      _pendingEchoRpc.add(rpcId);
      _lastSentText = text;
      _lastSentAt = DateTime.now();
      return rpcId;
    } catch (e) {
      agentRunning = false;
      notifyListeners();
      rethrow;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    final sessionId = settings.sessionId;
    if (sessionId == null) return;
    try {
      await _api!.cancelSession(sessionId);
    } catch (e) {
      rethrow;
    } finally {
      agentRunning = false;
      activeTool = null;
      final idx = messages.indexWhere((m) => m.isStreaming);
      if (idx >= 0) {
        messages[idx] = messages[idx].copyWith(isStreaming: false);
      }
      notifyListeners();
    }
  }

  // ── 内部辅助 ────────────────────────────────────

  void _touchActivity() {
    final id = settings.sessionId;
    if (id == null) return;
    for (final s in sessions) {
      if (s['sessionId'] == id) {
        s['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        break;
      }
    }
  }
}
