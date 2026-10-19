import 'dart:async';

import '../utils/constants.dart';
import 'agent_backend.dart';
import 'model_catalog.dart';
import 'opencode/opencode_api.dart';
import 'opencode/opencode_mapper.dart';
import 'opencode/opencode_model_service.dart';
import 'opencode/opencode_stream.dart';

/// opencode 后端实现（与 DshBackend 同职责）
///
/// 三条数据通道：
/// 1. REST（[OpenCodeApi]）：会话列表/历史/发消息/中断/模型/审批应答；
/// 2. SSE（[OpenCodeStream]）：text 打字机、execution 态、tool、permission；
/// 3. active 轮询（5s）：补 running 标记 + 断线漏事件的兜底。
///
/// 断线重连后做全量对账（历史 + 待审批 + active + 列表），
/// 与 DSH 重连重拉 baseline 同一语义。
class OpenCodeBackend implements AgentBackend {
  final BackendContext ctx;
  final OpenCodeApi api;

  OpenCodeStream? _stream;
  OpenCodeModelService? _models;

  /// 当前绑定的会话
  String? _boundSessionId;

  /// 自己最后一次发送的 inbox 消息 id（回执对账，免重拉历史）
  String? _lastSentInboxId;

  /// 已知活跃会话集合（轮询边沿检测）
  final Set<String> _activeIds = {};
  Timer? _activeTimer;
  bool _reconciling = false;

  OpenCodeBackend(this.ctx, {OpenCodeApi? api})
      : api = api ??
            OpenCodeApi(
              baseUrl: ctx.server.httpUrl,
              password: ctx.server.token,
            );

  @override
  bool get connected => ctx.state.connected;

  @override
  ModelCatalogService? get models => _models;

  @override
  String? get activeSessionId => _boundSessionId ?? ctx.state.sessionId;

  // ── 打开 / 切换 ─────────────────────────────────

  @override
  Future<void> open(String? sessionId) async {
    await _teardown();
    if (sessionId == null || sessionId.isEmpty) {
      ctx.state.setConnecting(false);
      ctx.state.setConnected(false);
      return;
    }

    _boundSessionId = sessionId;
    ctx.state.setConnecting(true);
    ctx.state.setConnectionError(null);
    _models = OpenCodeModelService(api);

    // 1) 历史装载（asc 序；与 DSH onSnapshot 走同一段装载逻辑）
    try {
      final raw = await api.messages(sessionId);
      ctx.dispatcher.onHistoryLoaded(OpenCodeMapper.messagesToChat(raw));
    } catch (e) {
      // 历史拉不到不谎报连接态，但要把原因说出来
      ctx.state.setConnectionError('历史读取失败：$e');
    }

    // 2) 会话信息：标题 + 当前模型（opencode 无投影流，以 Info 为准）
    try {
      final info = await api.sessionInfo(sessionId);
      final title = info['title'] as String?;
      if (title != null && title.isNotEmpty) ctx.state.setSessionTitle(title);
      final sel = OpenCodeMapper.modelSelectionOf(info['model']);
      if (sel != null) ctx.state.setModelSelection(sel);
    } catch (_) {
      // 标题/模型缺失不阻塞连接
    }

    // 3) SSE 事件流
    _stream = OpenCodeStream(
      baseUrl: ctx.server.httpUrl,
      password: ctx.server.token,
    );
    _wireStream();
    _stream!.connect();

    // 4) active 轮询：补 running + 断线兜底
    _activeTimer = Timer.periodic(opencodeActivePollInterval, (_) => _pollActive());
    await _pollActive();
  }

  Future<void> _teardown() async {
    _activeTimer?.cancel();
    _activeTimer = null;
    _stream?.dispose();
    _stream = null;
    _activeIds.clear();
    _lastSentInboxId = null;
  }

  void _wireStream() {
    final s = _stream!;
    s.onConnected = () {
      ctx.state.setConnecting(false);
      ctx.state.setConnected(true);
      // （重）连上：全量对账（历史 + 待审批 + running + 列表）
      _reconcileAll();
    };
    s.onDisconnected = () {
      ctx.state.setConnected(false);
    };
    s.onError = (message) {
      ctx.state.setConnectionError(message);
    };
    s.onEvent = _onEvent;
  }

  bool _isCurrent(String sid) =>
      sid.isNotEmpty && sid == (_boundSessionId ?? ctx.state.sessionId);

  // ── SSE 事件 → 统一入口 ──────────────────────────

  void _onEvent(String type, Map<String, dynamic> data) {
    OpenCodeMapper.mapEvent(
      type: type,
      data: data,
      sink: OpenCodeEventSink(
        onTextDelta: ctx.dispatcher.onTextDelta,
        onAssistantFinal: (text) => ctx.dispatcher.onAssistantFinal(text, false),
        onTurnStart: (sid) {
          if (_isCurrent(sid)) ctx.dispatcher.onTurnStart();
          ctx.dispatcher.onSessionStatus(sid, true);
        },
        onTurnEnd: (sid) {
          if (_isCurrent(sid)) ctx.dispatcher.onTurnEnd();
          ctx.dispatcher.onSessionStatus(sid, false);
          ctx.onRefreshSessions();
        },
        onToolCall: (name, args) => ctx.dispatcher.onToolCall(name, args),
        onToolResult: ctx.dispatcher.onToolResult,
        onApproval: ({
          required String sessionId,
          required String approvalId,
          required String action,
          required List<String> resources,
          String? message,
        }) {
          ctx.dispatcher.onApproval(
            rpcId: approvalId,
            sessionId: sessionId,
            approvalId: approvalId,
            toolName: action,
            reason: OpenCodeMapper.approvalReason(resources, message),
          );
          // 事件载荷与 GET /api/permission/request 同构，再拉一次列表对账
          _reconcilePermissions();
        },
        onApprovalResolved: ctx.dispatcher.onApprovalResolved,
        onUserEcho: (inboxId) async {
          // 自己刚发的消息已有乐观气泡，不重拉
          if (inboxId == _lastSentInboxId) return;
          await _reloadHistory();
          await ctx.onRefreshSessions();
        },
        onSessionCreated: (_) => ctx.onRefreshSessions(),
        onSessionRenamed: (sid, title) {
          if (_isCurrent(sid)) ctx.state.setSessionTitle(title);
          ctx.onRefreshSessions();
        },
      ),
    );
  }

  // ── 全量对账 / 轮询 ─────────────────────────────

  /// 断线重连后的全量对账（漏事件的兜底）
  Future<void> _reconcileAll() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      await _reloadHistory();
      await _reconcilePermissions();
      await _pollActive();
      await ctx.onRefreshSessions();
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _reloadHistory() async {
    final sid = _boundSessionId;
    if (sid == null || sid.isEmpty) return;
    try {
      final raw = await api.messages(sid);
      ctx.dispatcher.onHistoryLoaded(OpenCodeMapper.messagesToChat(raw));
    } catch (_) {
      // 重连瞬间拉历史失败：等下一个对账周期，不清空已有消息
    }
  }

  /// 待审批对账：以 GET /api/permission/request 为权威，
  /// 漏 event 能补上，已应答/已拒绝的能消掉。
  Future<void> _reconcilePermissions() async {
    List<Map<String, dynamic>> list;
    try {
      list = await api.permissionRequests();
    } catch (_) {
      return; // 拉不到不做任何增删（宁可漏，不可错杀）
    }
    final live = <String>{};
    for (final p in list) {
      final id = p['id'] as String? ?? '';
      if (id.isEmpty) continue;
      live.add(id);
      // 已在状态中枢的不重复添加（避免重复响铃/通知）
      if (ctx.state.approvals.any((a) => a.approvalId == id)) continue;
      final resources =
          (p['resources'] as List?)?.whereType<String>().toList() ?? const [];
      ctx.dispatcher.onApproval(
        rpcId: id,
        sessionId: p['sessionID'] as String? ?? '',
        approvalId: id,
        toolName: p['action'] as String? ?? 'tool',
        reason: OpenCodeMapper.approvalReason(
            resources, p['message'] as String?),
      );
    }
    for (final a in ctx.state.approvals.toList()) {
      if (!live.contains(a.approvalId)) {
        ctx.dispatcher.onApprovalResolved(a.approvalId);
      }
    }
  }

  /// active 轮询：边沿检测 → dispatcher.onSessionStatus
  /// （实时侧 SSE 已覆盖大部分，这里兜底 + 修打开前就在跑的会话）
  Future<void> _pollActive() async {
    Set<String> ids;
    try {
      ids = await api.activeSessions();
    } catch (_) {
      return;
    }
    for (final id in ids) {
      if (_activeIds.add(id)) ctx.dispatcher.onSessionStatus(id, true);
    }
    for (final id in _activeIds.toList()) {
      if (!ids.contains(id)) {
        _activeIds.remove(id);
        ctx.dispatcher.onSessionStatus(id, false);
      }
    }
  }

  // ── 会话操作 ────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> listSessions() async {
    final items = await api.listSessions();
    final active = await api.activeSessions();
    return items
        .map((i) => OpenCodeMapper.normalizeSession(i, activeIds: active))
        .toList();
  }

  @override
  Future<String> createSession({String? cwd}) async {
    final info = await api.createSession();
    final id = info['id'] as String? ?? '';
    if (id.isEmpty) throw const OpenCodeException('创建会话失败：响应里没有 id');
    return id;
  }

  @override
  Future<void> sendPrompt({
    required String sessionId,
    required String text,
    required String requestId,
  }) async {
    final inboxId = await api.sendPrompt(sessionId, text);
    _lastSentInboxId = inboxId.isNotEmpty ? inboxId : null;
    // opencode 的 durable 消息不带 rpcId，POST 成功即服务端已收 → 就地确认
    ctx.dispatcher.confirmLocalUserMessage(requestId);
  }

  @override
  Future<void> cancel(String sessionId) async {
    await api.interrupt(sessionId);
  }

  // ── 审批 ────────────────────────────────────────

  @override
  Future<bool> replyApproval({
    required String sessionId,
    required String approvalId,
    required bool allow,
  }) async {
    // once = 本次允许；reject = 拒绝（opencode 无 DSH 的 once/reject 二元外的语义）
    return api.replyPermission(
      sessionId,
      approvalId,
      allow ? 'once' : 'reject',
    );
  }

  @override
  Future<void> dispose() async {
    await _teardown();
  }
}
