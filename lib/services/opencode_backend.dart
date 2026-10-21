import 'dart:async';

import '../utils/constants.dart';
import 'agent_backend.dart';
import 'model_catalog.dart';
import 'opencode/opencode_api.dart';
import 'opencode/opencode_form_api.dart';
import 'opencode/opencode_mapper.dart';
import 'opencode/opencode_model_service.dart';
import 'opencode/opencode_reconciler.dart';
import 'opencode/opencode_stream.dart';
import 'opencode_stream_wiring.dart';

/// opencode 后端实现（与 DshBackend 同职责）：REST（[OpenCodeApi] +
/// [OpenCodeFormApi]）管列表/历史/发送/中断/模型/审批/表单（创建、应答靠
/// 轮询对账，取消才有事件），SSE（[OpenCodeStream]）管打字机与执行事件，
/// 5s 轮询补 running 标记 + 断线漏事件兜底。
///
/// 断线重连做全量对账（历史+待审批+active+表单+列表），与 DSH 重连重拉
/// baseline 同一语义；对账在 [OpenCodeReconciler]，装配在 [OpenCodeWiring]。
class OpenCodeBackend implements AgentBackend {
  final BackendContext ctx;

  late final OpenCodeApi api;
  late final OpenCodeFormApi formApi;

  OpenCodeStream? _stream;
  OpenCodeModelService? _models;
  OpenCodeWiring? _wiring;
  late final OpenCodeReconciler _reconciler;

  /// 当前绑定的会话
  String? _boundSessionId;

  /// 自己最后一次发送的 inbox 消息 id（回执对账，免重拉历史）
  String? _lastSentInboxId;

  Timer? _pollTimer;

  OpenCodeBackend(this.ctx) {
    final base = ctx.server.httpUrl;
    final pass = ctx.server.token;
    api = OpenCodeApi(baseUrl: base, password: pass);
    formApi = OpenCodeFormApi(baseUrl: base, password: pass);
    _reconciler = OpenCodeReconciler(api, formApi, ctx, () => _boundSessionId);
  }

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

    // 历史/信息/对账三路互不依赖，全部并行发起（隧道上每个串行等待都是一轮往返）；
    // pollF 的错误监听创建时就挂上（晚于完成会算未处理异常），最后原样上抛。
    final historyF = api.messages(sessionId);
    final infoF = api.sessionInfo(sessionId);
    Object? pollErr; StackTrace? pollSt;
    final pollF = _reconciler
        .pollActive()
        .then((_) => _reconciler.reconcileForms())
        .then<void>((_) {}, onError: (Object e, StackTrace s) {
      pollErr = e;
      pollSt = s;
    });

    _startStream();

    // active + 表单轮询：补 running / 发现 pending 表单 + 断线兜底
    _pollTimer = Timer.periodic(opencodeActivePollInterval, (_) => _pollCycle());

    // 1) 历史装载（asc 序；与 DSH onSnapshot 同段装载）；拉不到不谎报
    //    连接态，但要把原因说出来
    try {
      final raw = await historyF;
      ctx.dispatcher.onHistoryLoaded(OpenCodeMapper.messagesToChat(raw));
    } catch (e) {
      ctx.state.setConnectionError('历史读取失败：$e');
    }

    // 2) 会话信息：标题 + 当前模型（opencode 无投影流，以 Info 为准）；
    //    缺失不阻塞连接
    try {
      final info = await infoF;
      final title = info['title'] as String?;
      if (title != null && title.isNotEmpty) ctx.state.setSessionTitle(title);
      final sel = OpenCodeMapper.modelSelectionOf(info['model']);
      if (sel != null) ctx.state.setModelSelection(sel);
    } catch (_) {}

    // 3) 收尾对账，出错照旧从 open() 上抛
    await pollF;
    if (pollErr != null) Error.throwWithStackTrace(pollErr!, pollSt!);
  }

  /// SSE 装配：尽早发出去握手，不阻塞历史/信息装载
  void _startStream() {
    _stream = OpenCodeStream(
      baseUrl: ctx.server.httpUrl,
      password: ctx.server.token,
    );
    _wiring = OpenCodeWiring(
      ctx: ctx,
      isCurrent: _isCurrent,
      isOwnEcho: (inboxId) => inboxId == _lastSentInboxId,
      onTurnEdge: () => _reconciler.reconcileForms(),
      onApprovalEvent: () => _reconciler.reconcilePermissions(),
      onForeignEcho: _reconciler.reloadHistory,
      onStreamConnected: _onStreamConnected,
      onStreamDisconnected: () {
        // 指数退避重连由 stream 自理；这里只如实反映状态
        ctx.state.setConnected(false);
      },
      onStreamError: (message) {
        ctx.state.setConnectionError(message);
        ctx.state.setConnected(false);
      },
    );
    _wiring!.attach(_stream!);
    _stream!.connect();
  }

  Future<void> _teardown() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _stream?.dispose();
    _stream = null;
    _wiring = null;
    _reconciler.resetActive();
    _lastSentInboxId = null;
  }

  bool _isCurrent(String sid) =>
      sid.isNotEmpty && sid == (_boundSessionId ?? ctx.state.sessionId);

  /// SSE 流就绪 = 真正连上（与 DSH 的 onReady 同语义）。
  /// REST 历史已装载、SSE 已握手，这里统一落连接态 + 全量对账兜漏事件。
  Future<void> _onStreamConnected() async {
    ctx.state.setConnecting(false);
    ctx.state.setConnectionError(null);
    ctx.state.setConnected(true);
    await _reconciler.reconcileAll();
  }

  // ── 周期轮询 ────────────────────────────────────

  /// active + 表单一周期（两个通道都对账，共用一个定时器）
  Future<void> _pollCycle() async {
    await _reconciler.pollActive();
    await _reconciler.reconcileForms();
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
    final info = await api.createSession(cwd: cwd);
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

  // ── 表单（opencode 独有；DSH 无对应物） ──────────

  /// 应答表单。返回 true = 已提交或已被解决（409/404 都算关闭）；
  /// 答案不合法（400）上抛 [OpenCodeException]，message 可直显。
  Future<bool> submitForm(
    String formId,
    Map<String, dynamic> answer,
  ) async {
    final sid = _boundSessionId ?? ctx.state.sessionId ?? '';
    final ok = await formApi.replyForm(sid, formId, answer);
    // 204 = 已提交；false = 别人已答/已消失——本地都移除，UI 安静关闭
    ctx.dispatcher.onFormResolved(formId);
    return ok;
  }

  /// 放弃回答：通知 Agent 后本地移除（先移除，不让用户对已放弃的表单操作）
  Future<void> cancelForm(String formId, {String? message}) async {
    final sid = _boundSessionId ?? ctx.state.sessionId ?? '';
    ctx.dispatcher.onFormResolved(formId);
    await formApi.cancelForm(sid, formId, message: message);
  }

  @override
  Future<void> dispose() async {
    await _teardown();
  }
}
