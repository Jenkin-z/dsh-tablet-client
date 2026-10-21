part of 'session_state.dart';

// 审批 / 提问 / 表单（SessionState 的 part 文件）
//
// Web 端语义（见 DSH_APPROVAL_QUESTIONS_PORTING_SPEC.md）：
// · 每个会话各持有自己的待办，**不同会话的请求互不覆盖**
// · 界面同一时刻只展示「当前会话」的那一个
// · 同一会话内按优先级选举：plan-review > question > approval
// · 落选者不丢弃，等获胜者消解后重新浮出
//
// 方法用 `mixin X on _SessionStateCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin SessionStatePending on _SessionStateCore {
  final List<PendingApproval> _approvals = [];
  final List<PendingQuestion> _questions = [];
  final List<PendingForm> _forms = [];
  bool _questionDialogOpen = false;
  bool _formDialogOpen = false;

  List<PendingApproval> get approvals => List.unmodifiable(_approvals);

  /// 全部待回答问题（含其它会话）
  List<PendingQuestion> get allQuestions => List.unmodifiable(_questions);

  /// 当前会话待回答的问题（按优先级选举）
  PendingQuestion? get question {
    final sid = _sessionId;
    PendingQuestion? best;
    for (final q in _questions) {
      if (q.sessionId != sid) continue;
      if (best == null || _questionPriority(q) > _questionPriority(best)) {
        best = q;
      }
    }
    return best;
  }

  /// 其它会话是否有待处理的提问（用于侧栏提示）
  bool get hasForeignQuestion {
    final sid = _sessionId;
    return _questions.any((q) => q.sessionId != sid);
  }

  bool get questionDialogOpen => _questionDialogOpen;

  /// plan-review 优先于普通提问
  int _questionPriority(PendingQuestion q) => q.isPlanReview ? 1 : 0;

  void addApproval(PendingApproval approval) {
    // 同 approvalId 只保留一份
    if (_approvals.any((a) => a.approvalId == approval.approvalId)) return;
    _approvals.add(approval);
    notifyListeners();
  }

  void removeApproval(String approvalId) {
    final before = _approvals.length;
    _approvals.removeWhere((a) => a.approvalId == approvalId);
    if (_approvals.length != before) notifyListeners();
  }

  void clearApprovals() {
    if (_approvals.isEmpty) return;
    _approvals.clear();
    notifyListeners();
  }

  void addQuestion(PendingQuestion value) {
    // 同 rpcId 只保留一份
    if (_questions.any((q) => q.rpcId == value.rpcId)) return;
    _questions.add(value);
    notifyListeners();
  }

  void removeQuestion(String rpcId) {
    final before = _questions.length;
    _questions.removeWhere((q) => q.rpcId == rpcId);
    if (_questions.length != before) notifyListeners();
  }

  void setQuestionDialogOpen(bool value) {
    if (_questionDialogOpen == value) return;
    _questionDialogOpen = value;
    notifyListeners();
  }

  // ── opencode 表单（与提问对称：按会话隔离 + 当前会话选举）──────

  /// 全部待回答表单（含其它会话）
  List<PendingForm> get allForms => List.unmodifiable(_forms);

  /// 当前会话待回答的表单（先进先出：最早的 pending 排最前）
  PendingForm? get form {
    final sid = _sessionId;
    for (final f in _forms) {
      if (f.sessionId == sid) return f;
    }
    return null;
  }

  /// 其它会话是否有待处理的表单（用于侧栏提示）
  bool get hasForeignForm {
    final sid = _sessionId;
    return _forms.any((f) => f.sessionId != sid);
  }

  bool get formDialogOpen => _formDialogOpen;

  void addForm(PendingForm value) {
    // 同 formId 只保留一份（轮询对账与 SSE 可能重复送达）
    if (_forms.any((f) => f.formId == value.formId)) return;
    _forms.add(value);
    notifyListeners();
  }

  void removeForm(String formId) {
    final before = _forms.length;
    _forms.removeWhere((f) => f.formId == formId);
    if (_forms.length != before) notifyListeners();
  }

  void clearForms() {
    if (_forms.isEmpty) return;
    _forms.clear();
    notifyListeners();
  }

  void setFormDialogOpen(bool value) {
    if (_formDialogOpen == value) return;
    _formDialogOpen = value;
    notifyListeners();
  }

  // ── 批量更新 ────────────────────────────────────

  /// 某会话待处理的交互类型，用于列表状态点。
  ///
  /// 优先级与 Web 端一致：计划待审 > 等待回答 > 等待审批，
  /// 且**高于 running** —— 有待办时不再显示「运行中」。
  String? pendingKindOf(String sessionId) {
    var hasQuestion = false;
    for (final q in _questions) {
      if (q.sessionId != sessionId) continue;
      if (q.isPlanReview) return 'plan-review';
      hasQuestion = true;
    }
    if (hasQuestion) return 'question';
    // opencode 表单与 DSH 提问同级：都在等用户回答
    if (_forms.any((f) => f.sessionId == sessionId)) return 'question';
    for (final a in _approvals) {
      if (a.sessionId == sessionId) return 'approval';
    }
    return null;
  }

  /// 存在任何待处理交互的会话集合
  Set<String> get pendingSessionIds {
    final ids = <String>{};
    for (final a in _approvals) {
      ids.add(a.sessionId);
    }
    for (final q in _questions) {
      ids.add(q.sessionId);
    }
    for (final f in _forms) {
      ids.add(f.sessionId);
    }
    return ids;
  }
}
