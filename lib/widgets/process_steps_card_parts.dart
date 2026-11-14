part of 'process_steps_card.dart';

/// 时间线单行：左侧状态节点 + 连接线，右侧内容
///
/// 工具条目 = 折叠行（图标+工具名+状态）+ 点击展开参数（DESIGN.md §6）。
class _ProcessTimelineRow extends StatefulWidget {
  final ProcessEntry entry;

  /// 最后一条且卡处于展开态时不画向下连接线
  final bool isLast;

  const _ProcessTimelineRow({required this.entry, required this.isLast});

  @override
  State<_ProcessTimelineRow> createState() => _ProcessTimelineRowState();
}

class _ProcessTimelineRowState extends State<_ProcessTimelineRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: _buildNode(context, p),
                ),
                if (!widget.isLast)
                  Expanded(child: Container(width: 1, color: p.separator)),
              ],
            ),
          ),
          const SizedBox(width: IosTheme.spaceS),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: IosTheme.spaceS, top: 2),
              child: _buildContent(context, p),
            ),
          ),
        ],
      ),
    );
  }

  // ── 节点：running 转圈 / done 绿勾 / failed 红叉 / stopped 灰停 ──

  Widget _buildNode(BuildContext context, IosPalette p) {
    final entry = widget.entry;
    if (entry.kind == ProcessEntryKind.tool && entry.isRunning) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final (icon, color) = switch (entry.status) {
      ProcessEntryStatus.failed => (Icons.close, p.bad),
      ProcessEntryStatus.stopped => (Icons.stop_circle_outlined, p.label3),
      _ => entry.kind == ProcessEntryKind.reasoning
          ? (Icons.psychology_outlined, p.label3)
          : (Icons.check, p.ok),
    };
    return Icon(icon, size: 13, color: color);
  }

  // ── 内容 ───────────────────────────────────────

  Widget _buildContent(BuildContext context, IosPalette p) {
    final entry = widget.entry;
    if (entry.kind != ProcessEntryKind.tool) {
      // 过程文本 / 思考：灰字截断；思考内容可展开
      final body = Text(
        entry.text,
        maxLines: _expanded ? null : 3,
        overflow: _expanded ? null : TextOverflow.ellipsis,
        style: TextStyle(
          color: p.label2,
          fontSize: IosType.footnotePlus,
          height: 1.45,
        ),
      );
      if (entry.kind == ProcessEntryKind.text) return body;
      return InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '思考',
              style: TextStyle(
                color: p.label3,
                fontSize: IosType.caption,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            body,
          ],
        ),
      );
    }
    // 工具行：名称 · 摘要（可展开完整参数）
    return InkWell(
      onTap: entry.toolDetail == null
          ? null
          : () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: entry.toolName,
                  style: TextStyle(
                    color: p.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (entry.toolDetail != null && !_expanded)
                  TextSpan(
                    text: ' · ${entry.toolDetail}',
                    style: TextStyle(color: p.label3),
                  ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.label,
              fontSize: IosType.footnotePlus,
              height: 1.4,
            ),
          ),
          if (_expanded && entry.toolDetail != null) ...[
            const SizedBox(height: IosTheme.spaceXS),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(IosTheme.spaceS),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(IosTheme.radiusXS),
              ),
              child: AdaptiveSelectableText(
                entry.toolDetail!,
                style: TextStyle(
                  fontFamily: IosType.mono,
                  color: p.label2,
                  fontSize: IosType.caption,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
