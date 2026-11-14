import 'package:flutter/material.dart';
import '../models/process_step.dart';
import '../theme/ios_theme.dart';
import 'adaptive_selectable_text.dart';

part 'process_steps_card_parts.dart';

/// 过程步骤卡：当前 turn 的执行过程（DESIGN.md §6：垂直时间线）
///
/// 运行中展开实时显示（过程文本 + 思考 + 工具调用及状态），
/// turn 收尾后收起成一行摘要，可点击展开回看。
class ProcessStepsCard extends StatefulWidget {
  final List<ProcessEntry> entries;

  /// turn 是否已收尾（收起态；运行中恒为展开）
  final bool collapsed;

  const ProcessStepsCard({
    super.key,
    required this.entries,
    required this.collapsed,
  });

  @override
  State<ProcessStepsCard> createState() => _ProcessStepsCardState();
}

class _ProcessStepsCardState extends State<ProcessStepsCard> {
  /// 收起后用户手动展开的开关；自动收起/重新运行时复位
  bool _userExpanded = false;

  @override
  void didUpdateWidget(covariant ProcessStepsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != oldWidget.collapsed) {
      _userExpanded = false;
    }
  }

  bool get _expanded => !widget.collapsed || _userExpanded;

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        margin: const EdgeInsets.only(
          top: IosTheme.spaceXS,
          bottom: IosTheme.spaceXS,
          left: IosTheme.spaceS,
          right: IosTheme.spaceXXXL,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(IosTheme.radiusS),
          border: p.isDark ? Border.all(color: p.separator, width: 0.5) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: _expanded
              ? _buildExpanded(context, p)
              : _buildCollapsedHeader(context, p),
        ),
      ),
    );
  }

  // ── 收起态：一行摘要 ────────────────────────────

  Widget _buildCollapsedHeader(BuildContext context, IosPalette p) {
    final toolCount =
        widget.entries.where((e) => e.kind == ProcessEntryKind.tool).length;
    return InkWell(
      borderRadius: BorderRadius.circular(IosTheme.radiusS),
      onTap: () => setState(() => _userExpanded = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: IosTheme.spaceS,
          horizontal: IosTheme.spaceL,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt_outlined,
              size: 16,
              color: p.accent,
            ),
            const SizedBox(width: IosTheme.spaceS),
            Flexible(
              child: Text(
                '执行过程 · $toolCount 次工具调用',
                style: TextStyle(
                  color: p.label2,
                  fontSize: IosType.footnotePlus,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: p.label3),
          ],
        ),
      ),
    );
  }

  // ── 展开态：垂直时间线 ──────────────────────────

  Widget _buildExpanded(BuildContext context, IosPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: IosTheme.spaceS,
        horizontal: IosTheme.spaceL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.entries.length; i++)
            _ProcessTimelineRow(
              entry: widget.entries[i],
              isLast: i == widget.entries.length - 1 && !widget.collapsed,
            ),
          if (widget.collapsed)
            // 收起但被用户点开：给一个收回去的入口
            TextButton(
              onPressed: () => setState(() => _userExpanded = false),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '收起',
                style: TextStyle(color: p.accent, fontSize: IosType.footnote),
              ),
            ),
        ],
      ),
    );
  }
}
