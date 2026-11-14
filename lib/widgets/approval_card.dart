import 'package:flutter/material.dart';
import '../models/pending.dart';
import '../theme/ios_theme.dart';
import 'adaptive_selectable_text.dart';

export '../models/pending.dart' show PendingApproval;

/// 审批卡（DESIGN.md §6：描述 + 等宽块 + 「允许」accent 实心 /「拒绝」danger 描边）
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
    final p = IosPalette.of(context);
    final approval = widget.approval;
    // headline：reason 原文优先，否则工具越权描述（对齐 Web 端词汇）
    final headline =
        (approval.reason?.isNotEmpty ?? false) ? approval.reason! : '工具 ${approval.toolName} 请求越权执行';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceXS,
        IosTheme.spaceL,
        0,
      ),
      padding: const EdgeInsets.all(IosTheme.spaceM),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(IosTheme.radiusS),
        border: Border.all(color: p.warnTint.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _warningStrip(p),
          const SizedBox(height: IosTheme.spaceS),
          Text(
            headline,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: IosType.body,
              fontWeight: FontWeight.w500,
              color: p.label,
              height: 1.4,
            ),
          ),
          const SizedBox(height: IosTheme.spaceS),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: IosTheme.spaceM,
              vertical: IosTheme.spaceS,
            ),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(IosTheme.radiusXS),
            ),
            child: AdaptiveSelectableText(
              approval.toolName,
              style: TextStyle(
                fontFamily: IosType.mono,
                fontSize: IosType.footnotePlus,
                color: p.label2,
              ),
            ),
          ),
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
                    label: '拒绝',
                    destructive: true,
                    onPressed: _answering ? null : () => _answer(false),
                  ),
                ),
                const SizedBox(width: IosTheme.spaceM),
                Expanded(
                  child: IosButton(
                    label: '允许一次',
                    onPressed: _answering ? null : () => _answer(true),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 警告条：等待审批 + 呼吸点
  Widget _warningStrip(IosPalette p) {
    return Row(
      children: [
        IosBreathingDot(color: p.warnTint, size: 8),
        const SizedBox(width: IosTheme.spaceS),
        Text(
          '等待审批',
          style: TextStyle(
            fontSize: IosType.caption,
            fontWeight: FontWeight.w600,
            color: p.warnText,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Future<void> _answer(bool allow) async {
    // 同帧双击防重：rebuild 前 _answering 已同步为 true，入口检查挡重入
    //（重复应答会命中已解决的审批，弹出假的失败提示）
    if (_answering) return;
    setState(() => _answering = true);
    try {
      await widget.onAnswer(allow);
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }
}
