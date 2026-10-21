part of 'chat_controller.dart';

// 发送 / 取消 / 审批 / 提问 / opencode 表单（ChatController 的 part 文件）
//
// 方法用 `mixin ChatMessaging on ChatController` 挂载：mixin 与宿主类在
// 同一 library（part 机制），mixin 方法可访问宿主的私有字段。

mixin ChatMessaging on _ChatControllerCore {
  // ── 发送 / 取消 ─────────────────────────────────

  /// 当前后端实际连着的会话（权威值，而非设置里的期望值）
  String get _activeSessionId =>
      _backend?.activeSessionId ?? state.sessionId ?? '';

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

  // ── opencode 表单（opencode 独有；DSH 无对应物） ──

  /// 应答 opencode 表单。返回 true = 已提交或已被解决（UI 安静关闭）；
  /// 答案不合法时上抛（message 来自服务端，可直显）。
  Future<bool> submitForm(
    String formId,
    Map<String, dynamic> answer,
  ) async {
    final oc = _backend is OpenCodeBackend ? _backend as OpenCodeBackend : null;
    if (oc == null) return false;
    final ok = await oc.submitForm(formId, answer);
    if (state.formDialogOpen) {
      state.setFormDialogOpen(false);
    }
    return ok;
  }

  /// 放弃回答 opencode 表单：通知 Agent 后本地移除
  Future<void> cancelForm(String formId) async {
    // 先从界面移除，不让用户对着已放弃的表单继续操作
    state.removeForm(formId);
    if (state.formDialogOpen) {
      state.setFormDialogOpen(false);
    }
    final oc = _backend is OpenCodeBackend ? _backend as OpenCodeBackend : null;
    await oc?.cancelForm(formId, message: '用户放弃回答');
  }
}
