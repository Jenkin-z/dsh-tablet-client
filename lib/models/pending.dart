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

/// 待回答的 opencode 表单（Agent 通过 form 工具挂起 turn 提问；
/// 字段为服务端原始 shape，弹窗按 type 分发渲染）
class PendingForm {
  final String formId;
  final String sessionId;
  final String title;
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic>? metadata;

  const PendingForm({
    required this.formId,
    required this.sessionId,
    required this.title,
    required this.fields,
    this.metadata,
  });

  /// Agent 提问建的表单带 metadata.kind == 'question'；
  /// API 客户端建的不带——UI 上一视同仁，都允许回答/取消。
  bool get fromAgent => metadata?['kind'] == 'question';

  factory PendingForm.fromInfo(Map<String, dynamic> info) {
    return PendingForm(
      formId: info['id'] as String? ?? '',
      sessionId: info['sessionID'] as String? ?? '',
      title: info['title'] as String? ?? '表单',
      fields: (info['fields'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      metadata: info['metadata'] is Map
          ? Map<String, dynamic>.from(info['metadata'] as Map)
          : null,
    );
  }
}
