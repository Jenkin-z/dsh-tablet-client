part of 'chat_controller.dart';

/// 审批 / 问题管理 mixin（由 ChatController 混入）
///
/// 职责：waterfall 事件处理、审批应答、问题应答、过期检测。
mixin _ChatApprovalMixin on ChangeNotifier {
  // ── 子类必须提供的状态 ──────────────────────────
  List<PendingApproval> get approvals;
  PendingQuestion? get question;
  set question(PendingQuestion? q);
  bool get questionDialogOpen;
  set questionDialogOpen(bool v);
  bool get connected;
  SettingsService get settings;
  DshApi? get _api;
  MuxStream? get _mux;

  // ── UI 回调 ────────────────────────────────────
  VoidCallback? get onShowQuestionDialog;
  VoidCallback? get onPopQuestionDialog;

  // ── 通知辅助 ────────────────────────────────────

  /// 更新前台服务通知，让系统状态栏弹出提醒
  void _updateServiceNotification(String text) {
    try {
      FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }

  // ── 审批事件 ────────────────────────────────────

  void onApproval(
      ({
        String rpcId,
        String sessionId,
        String approvalId,
        String toolName,
        String? reason,
      }) rec) {
    if (rec.approvalId.isEmpty) return;
    if (approvals.any((a) => a.approvalId == rec.approvalId)) return;
    approvals.add(PendingApproval(
      rpcId: rec.rpcId,
      sessionId: rec.sessionId,
      approvalId: rec.approvalId,
      toolName: rec.toolName,
      reason: rec.reason,
    ));
    notifyListeners();
    // 系统通知
    _updateServiceNotification('需要确认：${rec.toolName}');
    if (settings.soundEnabled && settings.approvalSound) {
      SoundService.approval(customPath: settings.customSoundPath('approval'));
    }
  }

  void onApprovalResolved(String approvalId) {
    approvals.removeWhere(
        (a) => a.approvalId == approvalId || a.rpcId == approvalId);
    notifyListeners();
    if (approvals.isEmpty && question == null) {
      _updateServiceNotification('与 PC 端保持连接');
    }
  }

  Future<bool> answerApproval(PendingApproval a, bool allow) async {
    final ok =
        await (_mux?.respondApproval(a.rpcId, allow) ?? Future.value(false));
    if (ok) {
      approvals.removeWhere((x) => x.approvalId == a.approvalId);
      notifyListeners();
      if (approvals.isEmpty && question == null) {
        _updateServiceNotification('与 PC 端保持连接');
      }
    }
    return ok;
  }

  // ── 问题事件 ────────────────────────────────────

  void onQuestion(
      ({
        String rpcId,
        String sessionId,
        List<Map<String, dynamic>> questions,
      }) rec) {
    if (rec.rpcId.isEmpty || rec.questions.isEmpty) return;
    question = PendingQuestion(
      rpcId: rec.rpcId,
      sessionId: rec.sessionId,
      questions: rec.questions,
    );
    notifyListeners();
    // 系统通知
    _updateServiceNotification('有 ${rec.questions.length} 个问题待回答');
    if (settings.soundEnabled && settings.approvalSound) {
      SoundService.question(customPath: settings.customSoundPath('question'));
    }
    onShowQuestionDialog?.call();
  }

  void onQuestionResolved(String rpcId) {
    if (question?.rpcId == rpcId) {
      question = null;
      if (questionDialogOpen) {
        questionDialogOpen = false;
        onPopQuestionDialog?.call();
      }
      notifyListeners();
      if (approvals.isEmpty) {
        _updateServiceNotification('与 PC 端保持连接');
      }
    }
  }

  Future<bool> submitQuestion(List<Map<String, dynamic>> answers) async {
    final q = question;
    if (q == null) return false;
    final ok =
        await (_mux?.respondQuestion(q.rpcId, answers) ?? Future.value(false));
    if (ok) {
      question = null;
      notifyListeners();
    }
    return ok;
  }

  // ── 过期检测 ────────────────────────────────────

  void checkApprovalsStale(String? sessionId, int? cursor) {
    if (!connected || _api == null) return;
    if (sessionId == null) return;
    if (approvals.isEmpty && question == null) return;
    if (cursor == null) return;
    _api!.getHistory(sessionId, throughSeq: cursor, maxMessages: 10).then((result) {
      final events = result['events'] as List<dynamic>? ?? [];
      for (final e in events) {
        final ev = e as Map<String, dynamic>? ?? {};
        final event = ev['event'] as Map<String, dynamic>?;
        final type = event?['type'] as String? ?? '';
        if (type == 'turn/start' || type == 'assistant/message') {
          if (approvals.isNotEmpty || question != null) {
            approvals.clear();
            question = null;
            notifyListeners();
          }
          return;
        }
      }
    }).catchError((_) {});
  }
}
