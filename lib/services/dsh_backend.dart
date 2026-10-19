import 'dart:async';

import '../utils/constants.dart';
import '../utils/session_format.dart';
import 'agent_backend.dart';
import 'dsh/dsh_api.dart';
import 'dsh/mux_stream.dart';
import 'dsh/model_service.dart';
import 'model_catalog.dart';

/// DSH 后端实现：现有 DshApi + MuxStream 的装配
///
/// 从 ChatController 原样迁入（连接、状态迁移、审批应答），行为不变：
/// - mux 回调 → EventDispatcher（对账/状态迁移只有一份）
/// - 就绪/重连/一轮结束 → onRefreshSessions 校准列表
/// - 运行状态 → dispatcher.onSessionStatus（内部转 ServerManager）
class DshBackend implements AgentBackend {
  final BackendContext ctx;
  DshApi? _api;
  ModelService? _models;
  MuxStream? _mux;

  /// mux 实际连着的会话（权威值）
  String? _muxSessionId;
  Timer? _readyTimeout;

  DshBackend(this.ctx);

  @override
  bool get connected => ctx.state.connected;

  @override
  ModelCatalogService? get models => _models;

  @override
  String? get activeSessionId => _muxSessionId ?? ctx.state.sessionId;

  // ── 打开 / 重连 ─────────────────────────────────

  @override
  Future<void> open(String? sessionId) async {
    _mux?.dispose();
    _mux = null;

    final srv = ctx.server;
    if (sessionId == null || sessionId.isEmpty) {
      ctx.state.setConnecting(false);
      ctx.state.setConnected(false);
      return;
    }

    _api = DshApi(baseUrl: srv.httpUrl, cookie: srv.cookie);
    _models = ModelService(_api!);

    _muxSessionId = sessionId;
    ctx.state.setConnecting(true);

    _mux = MuxStream(
      wsBaseUrl: srv.httpUrl.replaceFirst('http', 'ws'),
      cookie: srv.cookie,
    )..sessionId = sessionId;

    _wireMux();

    await _mux!.connect();
    // 连接挂起时不至于永远停在「连接中」
    _readyTimeout?.cancel();
    _readyTimeout = Timer(connectReadyTimeout, () {
      if (!ctx.state.connected) {
        ctx.state.setConnecting(false);
        ctx.state.setConnectionError('连接超时，正在自动重试…');
      }
    });
  }

  void _wireMux() {
    final dispatcher = ctx.dispatcher;
    final state = ctx.state;
    _mux!
      ..onSnapshot = dispatcher.onSnapshot
      ..onProjections = (projections) {
        // 开窗投影里的标题是权威值，优先于本地推断
        final title = extractProjectionTitle(projections);
        if (title != null && title.isNotEmpty) {
          state.setSessionTitle(title);
        }
        // 重连后恢复当前模型（否则切换过的模型会显示回默认值）
        dispatcher.applySnapshotProjections(projections);
      }
      ..onTextDelta = dispatcher.onTextDelta
      ..onAssistantMessage = dispatcher.onAssistantMessage
      ..onAssistantFinal = dispatcher.onAssistantFinal
      ..onUserMessage = dispatcher.onUserMessage
      ..onApproval = dispatcher.onApproval
      ..onApprovalResolved = dispatcher.onApprovalResolved
      ..onQuestion = dispatcher.onQuestion
      ..onQuestionResolved = dispatcher.onQuestionResolved
      ..onToolView = dispatcher.onToolView
      ..onTurnStart = dispatcher.onTurnStart
      ..onToolCall = dispatcher.onToolCall
      ..onToolResult = dispatcher.onToolResult
      ..onTurnEnd = () {
        dispatcher.onTurnEnd();
        ctx.onRefreshSessions();
      }
      ..onQueueUpdate = dispatcher.onQueueUpdate
      ..onWorkspaceBaseline = dispatcher.onWorkspaceBaseline
      ..onSessionStatus = dispatcher.onSessionStatus
      ..onSessionError = (sessionId, message) {
        dispatcher.onSessionError?.call(sessionId, message);
      }
      ..onControlBaseline = dispatcher.onControlBaseline
      ..onProjectionChange = dispatcher.onProjectionChange
      ..onReady = () {
        // mux 真正就绪（clientId 已到手）才算连上
        state.setConnecting(false);
        state.setConnected(true);
        // 连上后校准一次数据基线：状态点的绿色必须建立在
        // 「列表确实拉到了」之上，而不是「socket 通了」。
        ctx.onRefreshSessions();
      }
      ..onReconnecting = () {
        state.setConnected(false);
      }
      ..onReconnected = () {
        state.setConnected(true);
        // 重连后重新校准（Web 端也是在重连时重拉 baseline 的）
        ctx.onRefreshSessions();
      }
      ..onDisconnected = () {
        state.setConnected(false);
      }
      ..onError = (message) {
        state.setConnectionError(message);
      };
  }

  // ── 会话操作 ────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> listSessions() async {
    final api = _api;
    if (api == null) return [];
    return api.listSessions();
  }

  @override
  Future<String> createSession({String? cwd}) async {
    final api = _api;
    if (api == null) throw StateError('未连接，无法新建会话');
    return api.createSession(cwd: cwd);
  }

  @override
  Future<void> sendPrompt({
    required String sessionId,
    required String text,
    required String requestId,
  }) async {
    final api = _api;
    if (api == null) throw StateError('未连接，消息已保留');
    await api.sendPrompt(sessionId, text, requestId: requestId);
  }

  @override
  Future<void> cancel(String sessionId) async {
    final api = _api;
    if (api == null) throw StateError('未连接，无法停止');
    await api.cancelSession(sessionId);
  }

  // ── 审批 / 提问 ─────────────────────────────────

  @override
  Future<bool> replyApproval({
    required String sessionId,
    required String approvalId,
    required bool allow,
  }) async {
    final ok = await _mux?.respondApproval(approvalId, allow);
    return ok ?? false;
  }

  /// 提问应答（DSH 独有；opencode 表单 v1 不在范围）
  Future<bool> respondQuestion(
      String rpcId, List<Map<String, dynamic>> answers) async {
    final ok = await _mux?.respondQuestion(rpcId, answers);
    return ok ?? false;
  }

  /// 放弃回答：显式通知 Host，避免请求一直挂着
  Future<bool> cancelQuestion(String rpcId) async {
    final ok = await _mux?.cancelQuestion(rpcId);
    return ok ?? false;
  }

  @override
  Future<void> dispose() async {
    _readyTimeout?.cancel();
    _mux?.dispose();
    _mux = null;
  }
}
