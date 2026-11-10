part of 'process_steps_card.dart';

/// 单条过程条目行：文本（灰字截断）或工具（状态图标 + 名称 · 摘要）
class _ProcessEntryRow extends StatelessWidget {
  final ProcessEntry entry;
  final bool isDark;

  const _ProcessEntryRow({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isText = entry.kind == ProcessEntryKind.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IosTheme.spaceXXS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, height: 16, child: _buildLeading(context)),
          const SizedBox(width: IosTheme.spaceS),
          Expanded(
            child: isText
                ? Text(
                    entry.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _mutedColor(context),
                          height: 1.4,
                        ),
                  )
                : _buildToolText(context),
          ),
        ],
      ),
    );
  }

  Color _mutedColor(BuildContext context) => isDark
      ? Colors.white.withValues(alpha: 0.6)
      : IosTheme.iosGray;

  /// 工具行：`名称 · 摘要`，摘要弱化
  Widget _buildToolText(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: entry.toolName),
          if (entry.toolDetail != null)
            TextSpan(
              text: ' · ${entry.toolDetail}',
              style: TextStyle(color: _mutedColor(context)),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            height: 1.4,
          ),
    );
  }

  /// 状态图标：running 转圈 / done 绿勾 / failed 红叉
  Widget _buildLeading(BuildContext context) {
    if (!entry.isRunning) {
      final failed = entry.status == ProcessEntryStatus.failed;
      return Icon(
        failed ? Icons.close : Icons.check,
        size: 15,
        color: failed ? IosTheme.iosRed : IosTheme.iosGreen,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: IosTheme.iosBlue,
      ),
    );
  }
}
