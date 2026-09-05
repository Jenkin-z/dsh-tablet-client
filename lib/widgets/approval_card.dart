import 'package:flutter/material.dart';

/// 待确认的审批请求
class PendingApproval {
  final String rpcId;
  final String sessionId;
  final String approvalId;
  final String toolName;
  final String? reason;
  bool answering = false;

  PendingApproval({
    required this.rpcId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    required this.reason,
  });
}

/// 审批确认卡：固定在输入栏上方，允许一次 / 拒绝
class ApprovalCard extends StatelessWidget {
  final PendingApproval approval;
  final bool isForeignSession;
  final Future<void> Function(bool allow) onAnswer;
  final VoidCallback onViewSession;

  const ApprovalCard({
    super.key,
    required this.approval,
    required this.isForeignSession,
    required this.onAnswer,
    required this.onViewSession,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '需要确认：${approval.toolName}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (approval.reason != null && approval.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(approval.reason!,
                maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (isForeignSession)
                OutlinedButton(
                  onPressed: onViewSession,
                  child: const Text('去该会话'),
                )
              else ...[
                FilledButton(
                  onPressed: approval.answering ? null : () => onAnswer(true),
                  child: approval.answering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('允许一次'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: approval.answering ? null : () => onAnswer(false),
                  child: const Text('拒绝'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}