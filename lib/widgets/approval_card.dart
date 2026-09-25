import 'package:flutter/material.dart';
import '../models/pending.dart';
import '../theme/ios_theme.dart';

export '../models/pending.dart' show PendingApproval;

/// 审批确认卡 —— iOS 风格
///
/// 固定在输入栏上方，允许一次 / 拒绝。
class ApprovalCard extends StatefulWidget {
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
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  bool _answering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final approval = widget.approval;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceXS,
        IosTheme.spaceL,
        0,
      ),
      padding: const EdgeInsets.all(IosTheme.spaceM),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF3A1A0A)
            : IosTheme.iosOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        border: Border.all(
          color: IosTheme.iosOrange.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: IosTheme.iosOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(IosTheme.radiusXS),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: IosTheme.iosOrange,
                ),
              ),
              const SizedBox(width: IosTheme.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '需要确认',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: IosTheme.iosOrange,
                      ),
                    ),
                    Text(
                      approval.toolName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (approval.reason != null && approval.reason!.isNotEmpty) ...[
            const SizedBox(height: IosTheme.spaceS),
            Text(
              approval.reason!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
          const SizedBox(height: IosTheme.spaceM),
          Row(
            children: [
              if (widget.isForeignSession)
                IosButton(
                  label: '去该会话',
                  filled: false,
                  onPressed: widget.onViewSession,
                )
              else ...[
                Expanded(
                  child: IosButton(
                    label: '允许一次',
                    icon: Icons.check_circle_outline,
                    onPressed: _answering ? null : () => _answer(true),
                  ),
                ),
                const SizedBox(width: IosTheme.spaceM),
                Expanded(
                  child: IosButton(
                    label: '拒绝',
                    icon: Icons.cancel_outlined,
                    destructive: true,
                    filled: false,
                    onPressed: _answering ? null : () => _answer(false),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _answer(bool allow) async {
    setState(() => _answering = true);
    try {
      await widget.onAnswer(allow);
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }
}
