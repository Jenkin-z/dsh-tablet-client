import 'package:flutter/material.dart';

import 'approval_card.dart';

/// 当前会话的审批回复卡片列表
///
/// 只展示属于当前会话的审批；其它会话的在侧栏以告警点提示（同 Web 端）。
class ChatApprovalList extends StatelessWidget {
  const ChatApprovalList({
    super.key,
    required this.approvals,
    required this.sessionId,
    required this.onAnswer,
    required this.onViewSession,
  });

  final List<PendingApproval> approvals;
  final String? sessionId;
  final Future<void> Function(PendingApproval approval, bool allow) onAnswer;
  final void Function(PendingApproval approval) onViewSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: approvals
          .where((a) => a.sessionId == sessionId)
          .map(
            (a) => ApprovalCard(
              approval: a,
              isForeignSession: false,
              onAnswer: (allow) async => onAnswer(a, allow),
              onViewSession: () => onViewSession(a),
            ),
          )
          .toList(),
    );
  }
}
