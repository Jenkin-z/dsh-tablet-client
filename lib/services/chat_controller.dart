import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_server.dart';
import '../models/pending.dart';
import '../utils/session_format.dart';
import 'agent_backend.dart';
import 'dsh_backend.dart';
import 'event_dispatcher.dart';
import 'model_catalog.dart';
import 'opencode_backend.dart';
import 'server_manager.dart';
import 'session_state.dart';
import 'settings_service.dart';

/// 聊天业务逻辑门面：按 AgentServer.kind 选后端，页面只跟这个类对话
///
/// 重构后：
/// - 公开 API（boot/switchSession/send/cancel/answerApproval…）与后端无关；
/// - 所有连线、状态迁移、审批应答收在各自 backend 内部
///   （DshBackend / OpenCodeBackend 同级实现 AgentBackend）；
/// - 所有状态都从 SessionState 读取，所有事件都经 EventDispatcher 分发；
/// - 通知/声音钩子挂在 EventDispatcher 上（构造时一次），后端无关。
class ChatController extends ChangeNotifier {
  final SettingsService settings;
  final ServerManager? manager;

  /// 全局唯一的状态中枢，由上层注入
  final SessionState state;

  /// 统一事件入口（与 state 同一实例生命周期）
  late final EventDispatcher dispatcher;

  /// 本地乐观气泡与 durable 消息对账用的 id 生成器
  static const _uuid = Uuid();

  AgentBackend? _backend;

  ChatController({
    required this.settings,
    required this.state,
    this.manager,
  }) {
    // dispatcher 与 state 共用同一实例，避免状态分裂
    dispatcher = EventDispatcher(
      state: state,
      onSessionStatusExternal: (sessionId, running) {
        // 权威中枢先落状态，再通知 ServerManager 实时刷新列表
        manager?.applySessionStatus(
          settings.activeServerId ?? '',
          sessionId,
          running,
        );
      },
    );
  }

  /// 模型目录 / 切换（未连接或后端不支持时为 null）
  ModelCatalogService? get models => _backend?.models;

  @override
  void dispose() {
    _backend?.dispose();
    dispatcher.dispose();
    super.dispose();
  }

  // ── 初始化 / 重连 ───────────────────────────────

  Future<void> boot() async {
    // 状态中枢是全局共享的：换 PC 会重建 ChatController，
    // 必须先清掉上一台的残留，否则控制台会读到过期状态。
    dispatcher.reset();
    state.reset();

    state.setConnecting(true);
    state.setConnectionError(null);

    final srv = settings.active;
    if (srv == null) {
      state.setConnecting(false);
      state.setConnected(false);
      state.setConnectionError('还没有 PC，去设置里添加。');
      return;
    }
    if (!srv.isPaired) {
      state.setConnecting(false);
      state.setConnected(false);
      state.setConnectionError(switch (srv.kind) {
        AgentKind.dsh => '需要配对：请先在 PC 上启动 dsh web，然后用启动令牌完成配对。',
        AgentKind.opencode => '需要授权：请在设置里重新添加 opencode（粘贴授权链接或填密码）。',
      });
      return;
    }
    if (settings.sessionId == null || settings.sessionId!.isEmpty) {
      // 有机器没会话：明说，别显示误导人的「正在重连」
      state.setConnecting(false);
      state.setConnected(false);
      state.setConnectionError('还没有会话：到设置里「新建会话」开始第一段对话。');
      return;
    }

    state.setSessionId(settings.sessionId);
    state.setSessionTitle(_defaultTitle(srv));

    await _markCurrentSeen(srv.id, settings.sessionId);

    await _backend?.dispose();
    _backend = _createBackend(srv);

    await _refreshSessions();
    await _backend!.open(settings.sessionId);
  }

  AgentBackend _createBackend(AgentServer srv) {
    final ctx = BackendContext(
      settings: settings,
      manager: manager,
      state: state,
      dispatcher: dispatcher,
      server: srv,
      onRefreshSessions: _refreshSessions,
    );
    return switch (srv.kind) {
      AgentKind.dsh => DshBackend(ctx),
      AgentKind.opencode => OpenCodeBackend(ctx),
    };
  }

  String _defaultTitle(AgentServer srv) => switch (srv.kind) {
        AgentKind.dsh => 'DSH Agent',
        AgentKind.opencode => 'opencode Agent',
      };

  /// 打开一个会话 = 读过它。
  ///
  /// 这是未读功能的**唯一出口**。此前 `settings.markSeen()` 只在
  /// settings_service 里定义、**从未被任何界面调用**，于是未读只能靠
  /// 「全部已读」清空；而那个按钮又只清 3 小时窗口内的，超窗的永远清不掉
  /// —— 这就是用户看到的「一直有未读、数字涨到 103」。
  Future<void> _markCurrentSeen(String serverId, String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) return;
    await settings.markSeen(settings.seenKey(serverId, sessionId));
  }

  Future<void> _refreshSessions() async {
    final backend = _backend;
    if (backend == null) return;
    state.setLoadingSessions(true);
    try {
      final items = await backend.listSessions();
      // 与 SessionMonitor 用同一个判定：子 Agent 会话和多余的空会话
      // 都不进任何列表（Web 端 sessionVisible() 的等价规则）
      state.setSessions(items
          .where((s) => isUserFacingSession(s,
              currentSessionId: settings.sessionId))
          .toList());
      state.setSessionTitle(_titleFor(settings.sessionId));
      // 拉到了才算数据侧健康 —— 状态点据此变绿
      state.setSessionsHealth(ok: true);
    } catch (e) {
      // 不再静默：列表失败就是降级，状态点会变橙并可点开看原因
      state.setSessionsHealth(ok: false, error: '会话列表读取失败：$e');
    } finally {
      state.setLoadingSessions(false);
    }
  }

  String _titleFor(String? sessionId) {
    final srv = settings.active;
    final fallback =
        srv == null ? 'DSH Agent' : _defaultTitle(srv);
    if (sessionId == null) return fallback;
    for (final s in state.sessions) {
      if (s['sessionId'] == sessionId) {
        return sessionTitleOf(s);
      }
    }
    return fallback;
  }

  // ── 会话操作 ────────────────────────────────────

  Future<void> switchSession(String sessionId) async {
    if (sessionId == _backend?.activeSessionId && state.connected) return;
    await settings.setSessionId(sessionId);
    state.setSessionId(sessionId);
    state.setSessionTitle(_titleFor(sessionId));
    // 打开即已读：切换会话也要清掉它的未读标记
    await _markCurrentSeen(settings.activeServerId ?? '', sessionId);
    dispatcher.reset();
    await _backend?.open(sessionId);
  }

  Future<void> createNewSession({String? cwd}) async {
    final backend = _backend;
    if (backend == null || !state.connected) return;
    try {
      final id = await backend.createSession(cwd: cwd);
      await _refreshSessions();
      await switchSession(id);
    } catch (e) {
      state.setConnectionError('新建会话失败：$e');
    }
  }

  // ── 发送 / 取消 ─────────────────────────────────

  /// 当前后端实际连着的会话（权威值，而非设置里的期望值）
  String get _activeSessionId => _backend?.activeSessionId ?? state.sessionId ?? '';

  /// 发送消息。
  ///
  /// 先本地乐观上屏（用同一个 rpcId 与 durable 消息对账），
  /// 再发请求；失败就把乐观气泡撤回并抛出，避免消息「假装发出去了」。
  Future<void> send(String text) async {
    final backend = _backend;
    if (backend == null) throw StateError('未连接，消息已保留');
    if (!state.connected) throw StateError('未连接，消息已保留');
    final sessionId = _activeSessionId;
    if (sessionId.isEmpty) throw StateError('没有可用会话');

    final rpcId = _uuid.v4();
    dispatcher.addLocalUserMessage(text, rpcId);
    try {
      await backend.sendPrompt(
        sessionId: sessionId,
        text: text,
        requestId: rpcId,
      );
    } catch (e) {
      dispatcher.failLocalUserMessage(rpcId);
      rethrow;
    }
  }

  /// 请求停止当前运行。
  ///
  /// 只发请求，**不修改本地 running 状态** —— Web 端要求以 Host 推来的
  /// 权威状态为准（InputBar.tsx:283 附近）。失败向上抛，由界面提示。
  Future<void> cancel() async {
    final backend = _backend;
    if (backend == null || !state.connected) {
      throw StateError('未连接，无法停止');
    }
    final sessionId = _activeSessionId;
    if (sessionId.isEmpty) {
      throw StateError('没有可停止的会话');
    }
    await backend.cancel(sessionId);
  }

  // ── 审批 / 提问 ─────────────────────────────────

  Future<bool> answerApproval(PendingApproval a, bool allow) async {
    final sessionId = a.sessionId.isEmpty ? _activeSessionId : a.sessionId;
    final ok = await _backend?.replyApproval(
          sessionId: sessionId,
          approvalId: a.approvalId,
          allow: allow,
        ) ??
        false;
    if (ok) {
      state.removeApproval(a.approvalId);
    }
    return ok;
  }

  /// 提问应答（DSH 独有；opencode 表单 v1 不在范围）
  Future<bool> submitQuestion(List<Map<String, dynamic>> answers) async {
    final q = state.question;
    if (q == null) return false;
    final dsh = _backend is DshBackend ? _backend as DshBackend : null;
    final ok = await dsh?.respondQuestion(q.rpcId, answers) ?? false;
    if (ok) {
      state.removeQuestion(q.rpcId);
      if (state.questionDialogOpen) {
        state.setQuestionDialogOpen(false);
      }
    }
    return ok;
  }

  /// 放弃回答：显式通知 Host，避免请求一直挂着
  Future<void> cancelQuestion() async {
    final q = state.question;
    if (q == null) return;
    // 先从界面移除，不让用户对着已放弃的卡片继续操作
    state.removeQuestion(q.rpcId);
    if (state.questionDialogOpen) {
      state.setQuestionDialogOpen(false);
    }
    final dsh = _backend is DshBackend ? _backend as DshBackend : null;
    await dsh?.cancelQuestion(q.rpcId);
  }
}
