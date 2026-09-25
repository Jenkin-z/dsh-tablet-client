/// 待确认的审批请求（immutable，纯数据）
class PendingApproval {
  final String rpcId;
  final String sessionId;
  final String approvalId;
  final String toolName;
  final String? reason;

  const PendingApproval({
    required this.rpcId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    required this.reason,
  });
}

/// 待回答的问题请求（一 ask 多问一批答，纯数据）
class PendingQuestion {
  final String rpcId;
  final String sessionId;
  final List<Map<String, dynamic>> questions;

  const PendingQuestion({
    required this.rpcId,
    required this.sessionId,
    required this.questions,
  });

  /// plan-review 意图：Web 端用专用卡片（通过/否决），
  /// 且按钮不提供自定义文本入口（PlanReviewPanel 无输入框）。
  bool get isPlanReview {
    if (questions.length != 1) return false;
    final q = questions.first;
    final intent = q['intent'];
    if (intent is! Map) return false;
    if (intent['kind'] != 'plan-review') return false;
    return (q['detail'] as String?)?.isNotEmpty == true;
  }

  /// plan-review 的「通过」选项标签（Host 指定）
  String? get approveLabel {
    if (!isPlanReview) return null;
    final intent = questions.first['intent'];
    if (intent is! Map) return null;
    return intent['approve'] as String?;
  }
}
