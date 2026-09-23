import 'package:flutter/material.dart';
import '../services/changes_tracker.dart';
import '../services/diff_util.dart';
import '../theme/ios_theme.dart';

/// 右侧变更栏 —— iOS 风格
///
/// 本会话的文件变更列表 + 行级 diff。
class ChangesDrawer extends StatefulWidget {
  final ChangesTracker tracker;

  const ChangesDrawer({super.key, required this.tracker});

  @override
  State<ChangesDrawer> createState() => _ChangesDrawerState();
}

class _ChangesDrawerState extends State<ChangesDrawer> {
  final Set<String> _open = {};

  @override
  Widget build(BuildContext context) {
    final items = widget.tracker.items;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosTheme.spaceXL,
                IosTheme.spaceL,
                IosTheme.spaceL,
                IosTheme.spaceXS,
              ),
              child: const Text(
                '变更',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // 统计信息
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosTheme.spaceXL,
                0,
                IosTheme.spaceL,
                IosTheme.spaceM,
              ),
              child: Text(
                items.isEmpty
                    ? '本会话暂无文件变更'
                    : '${items.length} 个文件${widget.tracker.pendingCount > 0 ? '（${widget.tracker.pendingCount} 待执行）' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  color: IosTheme.iosGray,
                ),
              ),
            ),
            // 分隔线
            Container(
              height: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            // 变更列表
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: IosTheme.iosGreen.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: IosTheme.spaceM),
                          Text(
                            '没有变更',
                            style: TextStyle(
                              fontSize: 16,
                              color: IosTheme.iosGray,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: IosTheme.spaceS,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _fileRow(items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(FileChange e) {
    final key = '${e.turn ?? 0}:${e.path}';
    final open = _open.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() {
              if (open) {
                _open.remove(key);
              } else {
                _open.add(key);
              }
            }),
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
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: IosTheme.iosGray3,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open) _diffBlock(e),
      ],
    );
  }

  Widget _diffBlock(FileChange e) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lines = unifiedDiff(e.oldText, e.newText);
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
