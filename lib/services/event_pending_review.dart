part of 'event_dispatcher.dart';

// ── 审批 / 提问 / 表单（event_pending_review.dart）────────────
//
// 只搬代码不改逻辑：
// - 审批严格二元 'allowed-once' / 'rejected'（见 docs/MUX_PROTOCOL.md）；
// - question 取消 = {kind:'rejected', error:{name:'UserQuestionError',
//   code:'ASK_CANCELLED'}}；
// - 优先级 plan-review(2) > question(1) > approval(0) 在 SessionState 维护；
// - 声音 / 系统通知挂在这里（后端无关，接第三个后端时白拿）。
// mixin 依赖字段声明在 [_EventDispatcherCore]（event_dispatcher.dart）。

mixin EventDispatcherPendingReview on _EventDispatcherCore {
  /// 审批到达。
  ///
  /// 声音 + 系统通知挂在**这里**（而不是各后端的接线里）：
  /// 两个后端行为天然一致，接第三个后端时白拿。
  void onApproval({
    required String rpcId,
    required String sessionId,
    required String approvalId,
    required String toolName,
    String? reason,
  }) {
    state.addApproval(PendingApproval(
      rpcId: rpcId,
      sessionId: sessionId,
      approvalId: approvalId,
      toolName: toolName,
      reason: reason,
    ));
    _touchActivity();
    SoundService.approval();
    NotificationService.show(
      id: 30000,
      title: '需要确认',
      body: '工具 $toolName 需要确认',
    );
  }

  void onApprovalResolved(String approvalId) {
    state.removeApproval(approvalId);
  }

  /// 提问到达（opencode 表单 v1 不在范围，钩子后端无关，接表单时白拿）
  void onQuestion({
    required String rpcId,
    required String sessionId,
    required List<Map<String, dynamic>> questions,
  }) {
    state.addQuestion(PendingQuestion(
      rpcId: rpcId,
      sessionId: sessionId,
      questions: questions,
    ));
    _touchActivity();
    SoundService.question();
    // 切到后台时提问也要弹通知，否则最小化时看不到提问
    if (!AppVisibility.foreground) {
      NotificationService.show(
        id: 30001,
        title: 'DSH 向你提问',
        body: questions.map((q) => q['question']).whereType<String>().join(' '),
      );
    }
    // 非当前会话的提问不入弹窗：Web 端只在侧栏显示告警点，落选者留在队列里
    if (state.sessionId == sessionId) {
      onShowQuestionDialog?.call();
    }
  }

  void onQuestionResolved(String rpcId) {
    final wasShown = state.question?.rpcId == rpcId && state.questionDialogOpen;
    state.removeQuestion(rpcId);
    if (wasShown && state.questionDialogOpen) {
      state.setQuestionDialogOpen(false);
      onPopQuestionDialog?.call();
    }
  }

  // ── opencode 表单（与提问对称：声音 / 通知 / 弹窗钩子） ──

  /// 表单待回答（opencode 轮询对账发现 pending form 时调用）
  void onForm(PendingForm form) {
    state.addForm(form);
    _touchActivity();
    SoundService.question();
    if (!AppVisibility.foreground) {
      NotificationService.show(
        id: 30002,
        title: 'opencode 表单待填写',
        body: form.title,
      );
    }
    // 非当前会话的表单不入弹窗：只留在队列里，等用户切过去
    if (state.sessionId == form.sessionId) {
      onShowFormDialog?.call();
    }
  }

  /// 表单已被解决（取消事件 / 应答成功 / 对账发现已消失）
  void onFormResolved(String formId) {
    final wasShown = state.form?.formId == formId && state.formDialogOpen;
    state.removeForm(formId);
    if (wasShown && state.formDialogOpen) {
      state.setFormDialogOpen(false);
      onPopFormDialog?.call();
    }
  }
}
