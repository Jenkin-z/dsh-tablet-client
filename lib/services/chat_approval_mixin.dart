part of 'chat_controller.dart';

/// 审批 / 问题管理 mixin（由 ChatController 混入）
///
/// 职责：waterfall 事件处理、审批应答、问题应答。
/// 卡片失效以 Host 的 `cancel` 帧为准；mux 重连时 Host 会重新投递仍 pending
/// 的 waterfall，因此连接时清空本地卡片即可，无需轮询探测过期。
mixin _ChatApprovalMixin on ChangeNotifier {
  // ── 子类必须提供的状态 ──────────────────────────
  List<PendingApproval> get approvals;
  PendingQuestion? get question;
  set question(PendingQuestion? q);
  bool get questionDialogOpen;
  set questionDialogOpen(bool v);
  SettingsService get settings;
  MuxStream? get _mux;

  // ── UI 回调 ────────────────────────────────────
  VoidCallback? get onShowQuestionDialog;
  VoidCallback? get onPopQuestionDialog;

  // ── 通知辅助 ────────────────────────────────────

  int _notifyId = 0;

  /// 双通道通知：本地弹窗 + 前台服务通知更新（后台也能收到）
  void _showNotification(String title, String body) {
    // 1. 本地 heads-up 通知
    try {
      NotificationService.show(id: _notifyId++, title: title, body: body);
    } catch (_) {}
    // 2. 同时更新前台服务通知文本（后台也能更新，确保通知可见）
    try {
      FlutterForegroundTask.updateService(notificationText: '$title: $body');
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
    // 系统弹出通知
    _showNotification('需要确认', '${rec.toolName} 等待审批');
    if (settings.soundEnabled && settings.approvalSound) {
      SoundService.approval(customPath: settings.customSoundPath('approval'));
    }
  }

  void onApprovalResolved(String approvalId) {
    approvals.removeWhere(
        (a) => a.approvalId == approvalId || a.rpcId == approvalId);
    notifyListeners();
  }

  Future<bool> answerApproval(PendingApproval a, bool allow) async {
    final ok =
        await (_mux?.respondApproval(a.rpcId, allow) ?? Future.value(false));
    if (ok) {
      approvals.removeWhere((x) => x.approvalId == a.approvalId);
      notifyListeners();
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
    // 系统弹出通知
    _showNotification('待回答问题', '${rec.questions.length} 个问题需要回答');
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
}
