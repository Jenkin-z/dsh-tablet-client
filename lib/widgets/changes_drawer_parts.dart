import 'package:flutter/material.dart';

import '../services/changes_tracker.dart';
import '../services/diff_util.dart';
import '../theme/ios_theme.dart';

/// 变更抽屉里的单个文件行（含展开后的 diff）
///
/// 从 changes_drawer.dart 拆出来，让那个文件守住 200 行上限。
/// 展开状态由外层持有（[isOpen] + [onToggle]），本组件只负责画。
class ChangesFileRow extends StatelessWidget {
  final FileChange change;
  final bool isOpen;
  final VoidCallback onToggle;

  const ChangesFileRow({
    super.key,
    required this.change,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final e = change;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceL,
                vertical: IosTheme.spaceM,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: e.done
                          ? IosTheme.iosGreen.withValues(alpha: 0.12)
                          : IosTheme.iosOrange.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(IosTheme.radiusXS),
                    ),
                    child: Icon(
                      e.oldText == null
                          ? Icons.note_add_outlined
                          : Icons.edit_outlined,
                      size: 16,
                      color: e.done ? IosTheme.iosGreen : IosTheme.iosOrange,
                    ),
                  ),
                  const SizedBox(width: IosTheme.spaceM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.done ? '已应用' : '待执行'} · ${e.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: IosTheme.iosGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: IosTheme.iosGray3,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isOpen) ChangesDiffBlock(change: e),
      ],
    );
  }
}

/// 行级 unified diff 区块
///
/// 从 changes_drawer.dart 拆出来，让那个文件守住 200 行上限。
class ChangesDiffBlock extends StatelessWidget {
  final FileChange change;

  const ChangesDiffBlock({super.key, required this.change});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lines = unifiedDiff(change.oldText, change.newText);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        0,
        IosTheme.spaceL,
        IosTheme.spaceM,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(IosTheme.radiusXS),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in lines) _diffLine(l, isDark),
        ],
      ),
    );
  }

  Widget _diffLine(DiffLine l, bool isDark) {
    Color? bg;
    Color? textColor;
    String prefix = '  ';
    switch (l.op) {
      case DiffOp.add:
        bg = IosTheme.iosGreen.withValues(alpha: 0.1);
        textColor = IosTheme.iosGreen;
        prefix = '+ ';
        break;
      case DiffOp.del:
        bg = IosTheme.iosRed.withValues(alpha: 0.1);
        textColor = IosTheme.iosRed;
        prefix = '- ';
        break;
      case DiffOp.same:
        textColor = isDark ? Colors.white70 : Colors.black54;
        prefix = '  ';
        break;
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceM,
        vertical: IosTheme.spaceXXS,
      ),
      child: SelectableText(
        '$prefix${l.text}',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: textColor,
        ),
      ),
    );
  }
}
