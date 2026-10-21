import '../../models/pending.dart';
import '../agent_backend.dart';
import 'opencode_api.dart';
import 'opencode_form_api.dart';
import 'opencode_mapper.dart';

/// 对账族：断线重连 / 周期轮询时把服务端权威状态补齐到本地
///
/// 从 OpenCodeBackend 拆出（Service ≤ 250 行红线）。与 DSH 的对应物是
/// mux 重连重拉 baseline。
class OpenCodeReconciler {
  final OpenCodeApi api;
  final OpenCodeFormApi formApi;
  final BackendContext ctx;

  /// 当前绑定会话（可变，backend 持有真相）
  final String? Function() boundSessionId;

  /// 已知活跃会话集合（轮询边沿检测）
  final Set<String> _activeIds = {};

  bool _reconciling = false;

  OpenCodeReconciler(this.api, this.formApi, this.ctx, this.boundSessionId);

  /// 断线重连后的全量对账（漏事件的兜底）
  Future<void> reconcileAll() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      await reloadHistory();
      await reconcilePermissions();
      await pollActive();
      await reconcileForms();
      ctx.onRefreshSessions();
    } finally {
      _reconciling = false;
    }
  }

  Future<void> reloadHistory() async {
    final sid = boundSessionId();
    if (sid == null || sid.isEmpty) return;
    try {
      // 取**最近**一页：asc 会从会话开头取，长会话下重拉回来的还是旧消息
      final raw = await api.recentMessages(sid);
      ctx.dispatcher.onHistoryLoaded(OpenCodeMapper.messagesToChat(raw));
    } catch (_) {
      // 重连瞬间拉历史失败：等下一个对账周期，不清空已有消息
    }
  }

  /// 待审批对账：以 GET /api/permission/request 为权威，
  /// 漏 event 能补上，已应答/已拒绝的能消掉。
  Future<void> reconcilePermissions() async {
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
  Future<void> pollActive() async {
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

  /// 表单对账：发现 pending form → 入队（声音/通知/弹窗与 DSH 提问同套）
  ///
  /// 列表接口只回 Form.Info **不含 state**，逐个拉 detail 才知道 pending；
  /// 创建/应答无 SSE 事件（实测），这是发现提问的唯一通道。
  /// 只核实当前绑定会话——其他会话的 pending 无法用本接口确认，不错杀。
  Future<void> reconcileForms() async {
    final sid = boundSessionId();
    if (sid == null || sid.isEmpty) return;
    List<Map<String, dynamic>> list;
    try {
      list = await formApi.listForms(sid);
    } catch (_) {
      return; // 拉不到不增删（宁可漏，不可错杀）
    }
    final live = <String>{};
    for (final info in list) {
      final fid = info['id'] as String? ?? '';
      if (fid.isEmpty) continue;
      Map<String, dynamic> detail;
      try {
        detail = await formApi.formDetail(sid, fid);
      } catch (_) {
        continue; // 单个 detail 失败：跳过这个 form，不影响其余
      }
      final state = detail['state'];
      if (state is! Map || state['status'] != 'pending') continue;
      live.add(fid);
      if (ctx.state.allForms.any((f) => f.formId == fid)) continue; // 已入队不重复响铃
      ctx.dispatcher.onForm(PendingForm.fromInfo(detail));
    }
    for (final f in ctx.state.allForms.toList()) {
      if (f.sessionId == sid && !live.contains(f.formId)) {
        ctx.dispatcher.onFormResolved(f.formId);
      }
    }
  }

  void resetActive() => _activeIds.clear();
}
