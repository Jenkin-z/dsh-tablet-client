import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/pending.dart';
import '../utils/constants.dart';
import '../utils/session_format.dart';
import 'dsh_session_state.dart';
import 'mux_event_dispatcher.dart';
import 'mux_stream.dart';
import 'dsh_api.dart';
import 'model_service.dart';
import 'server_manager.dart';
import 'settings_service.dart';
import 'sound_service.dart';
import 'notification_service.dart';

/// 聊天业务逻辑控制器：管理连接、消息、审批、会话切换
///
/// 重构后：
/// - 所有状态都从 DshSessionState 读取
/// - 所有 mux 事件都通过 MuxEventDispatcher 分发
/// - 不再自己维护业务状态
class ChatController extends ChangeNotifier {
  final SettingsService settings;
  final ServerManager? manager;

  /// 全局唯一的状态中枢，由上层注入
  final DshSessionState state;
  late final MuxEventDispatcher dispatcher;

  /// 本地乐观气泡与 durable 消息对账用的 id 生成器
  static const _uuid = Uuid();

  // ── API / Stream ────────────────────────────────
  DshApi? _api;
  ModelService? _models;

  /// 模型目录 / 切换（未连接时为 null）
  ModelService? get models => _models;
  MuxStream? _mux;

  // ── 内部状态 ────────────────────────────────────
  String? _muxSessionId;
  Timer? _readyTimeout;

  ChatController({
    required this.settings,
    required this.state,
    this.manager,
  }) {
    // dispatcher 与 state 共用同一实例，避免状态分裂
    dispatcher = MuxEventDispatcher(state: state);
  }

  @override
  void dispose() {
    _readyTimeout?.cancel();
    _mux?.dispose();
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
    if (srv.unpaired) {
      state.setConnecting(false);
      state.setConnected(false);
      state.setConnectionError('需要配对：请先在 PC 上启动 dsh web，然后用启动令牌完成配对。');
      return;
    }

    _api = DshApi(baseUrl: srv.httpUrl, cookie: srv.cookie);
    _models = ModelService(_api!);
    state.setSessionId(settings.sessionId);

    await _refreshSessions();
    await _connectMux(settings.sessionId);
  }

  Future<void> _refreshSessions() async {
    if (_api == null) return;
    state.setLoadingSessions(true);
    try {
      final items = await _api!.listSessions();
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
    if (sessionId == null) return 'DSH Agent';
    for (final s in state.sessions) {
      if (s['sessionId'] == sessionId) {
        return sessionTitleOf(s);
      }
    }
    return 'DSH Agent';
  }

  // ── Mux 连接 ────────────────────────────────────

  Future<void> _connectMux(String? sessionId) async {
    _mux?.dispose();
    _mux = null;

    final srv = settings.active;
    if (srv == null || sessionId == null || sessionId.isEmpty) {
      state.setConnecting(false);
      state.setConnected(false);
      return;
    }

    _muxSessionId = sessionId;
    state.setConnecting(true);

    _mux = MuxStream(
      wsBaseUrl: srv.httpUrl.replaceFirst('http', 'ws'),
      cookie: srv.cookie,
    )..sessionId = sessionId;

    // 绑定回调
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
      ..onApproval = ({
        required String rpcId,
        required String sessionId,
        required String approvalId,
        required String toolName,
        String? reason,
      }) {
        dispatcher.onApproval(
          rpcId: rpcId,
          sessionId: sessionId,
          approvalId: approvalId,
          toolName: toolName,
          reason: reason,
        );
        SoundService.approval();
        NotificationService.show(
          id: 10000,
          title: '需要确认',
          body: '工具 $toolName 需要确认',
        );
      }
      ..onApprovalResolved = dispatcher.onApprovalResolved
      ..onQuestion = ({
        required String rpcId,
        required String sessionId,
        required List<Map<String, dynamic>> questions,
      }) {
        dispatcher.onQuestion(
          rpcId: rpcId,
          sessionId: sessionId,
          questions: questions,
        );
        SoundService.question();
      }
      ..onQuestionResolved = dispatcher.onQuestionResolved
      ..onToolView = dispatcher.onToolView
      ..onTurnStart = dispatcher.onTurnStart
      ..onToolCall = dispatcher.onToolCall
      ..onToolResult = dispatcher.onToolResult
      ..onTurnEnd = () {
        dispatcher.onTurnEnd();
        _refreshSessions();
      }
      ..onQueueUpdate = dispatcher.onQueueUpdate
      ..onWorkspaceBaseline = dispatcher.onWorkspaceBaseline
      ..onSessionStatus = (sessionId, running) {
        // 权威中枢先落状态，再通知 ServerManager 实时刷新列表
        dispatcher.onSessionStatus(sessionId, running);
        manager?.applySessionStatus(
          settings.activeServerId ?? '',
          sessionId,
          running,
        );
      }
      ..onSessionError = (sessionId, message) {
        dispatcher.onSessionError?.call(sessionId, message);
      }
      ..onControlBaseline = dispatcher.onControlBaseline
      ..onProjectionChange = dispatcher.onProjectionChange
      ..onReady = () {
        // mux 真正就绪（clientId 已到手）才算连上
        state.setConnecting(false);
        state.setConnected(true);
      }
      ..onReconnecting = () {
        state.setConnected(false);
      }
      ..onReconnected = () {
        state.setConnected(true);
      }
      ..onDisconnected = () {
        state.setConnected(false);
      }
      ..onError = (message) {
        state.setConnectionError(message);
      };

    await _mux!.connect();
    // 连接挂起时不至于永远停在「连接中」
    _readyTimeout?.cancel();
    _readyTimeout = Timer(connectReadyTimeout, () {
      if (!state.connected) {
        state.setConnecting(false);
        state.setConnectionError('连接超时，正在自动重试…');
      }
    });
  }

  // ── 会话操作 ────────────────────────────────────

  Future<void> switchSession(String sessionId) async {
    if (sessionId == _muxSessionId && state.connected) return;
    await settings.setSessionId(sessionId);
    state.setSessionId(sessionId);
    state.setSessionTitle(_titleFor(sessionId));
    dispatcher.reset();
    await _connectMux(sessionId);
  }

  Future<void> createNewSession({String? cwd}) async {
    if (_api == null || !state.connected) return;
    try {
      final id = await _api!.createSession(cwd: cwd);
      await _refreshSessions();
      await switchSession(id);
    } catch (e) {
      state.setConnectionError('新建会话失败：$e');
    }
  }

  // ── 发送 / 取消 ─────────────────────────────────

  /// 当前 mux 实际连着的会话（权威值，而非设置里的期望值）
  String get _activeSessionId => _muxSessionId ?? state.sessionId ?? '';

  /// 发送消息。
  ///
  /// 先本地乐观上屏（用同一个 rpcId 与 durable 消息对账），
  /// 再发 RPC；失败就把乐观气泡撤回并抛出，避免消息「假装发出去了」。
  Future<void> send(String text) async {
    if (_api == null) throw StateError('未连接，消息已保留');
    if (!state.connected) throw StateError('未连接，消息已保留');
    final sessionId = _activeSessionId;
    if (sessionId.isEmpty) throw StateError('没有可用会话');

    final rpcId = _uuid.v4();
    dispatcher.addLocalUserMessage(text, rpcId);
    try {
      await _api!.sendPrompt(sessionId, text, requestId: rpcId);
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
    if (_api == null || !state.connected) {
      throw StateError('未连接，无法停止');
    }
    final sessionId = _activeSessionId;
    if (sessionId.isEmpty) {
      throw StateError('没有可停止的会话');
    }
    await _api!.cancelSession(sessionId);
  }

  // ── 审批 / 提问 ─────────────────────────────────

  Future<bool> answerApproval(PendingApproval a, bool allow) async {
    final ok = await _mux?.respondApproval(a.approvalId, allow) ?? false;
    if (ok) {
      state.removeApproval(a.approvalId);
    }
    return ok;
  }

  Future<bool> submitQuestion(List<Map<String, dynamic>> answers) async {
    final q = state.question;
    if (q == null) return false;
    final ok = await _mux?.respondQuestion(q.rpcId, answers) ?? false;
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
    await _mux?.cancelQuestion(q.rpcId);
  }
}