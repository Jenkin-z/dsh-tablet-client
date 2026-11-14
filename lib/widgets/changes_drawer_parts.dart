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
    final p = IosPalette.of(context);
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
                      color: e.done ? p.okSoft : p.warnSoft,
                      borderRadius:
                          BorderRadius.circular(IosTheme.radiusXS),
                    ),
                    child: Icon(
                      e.oldText == null
                          ? Icons.note_add_outlined
                          : Icons.edit_outlined,
                      size: 16,
                      color: e.done ? p.ok : p.warnTint,
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
                          style: TextStyle(
                            fontFamily: IosType.mono,
                            fontSize: IosType.footnotePlus,
                            fontWeight: FontWeight.w500,
                            color: p.label,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.done ? '已应用' : '待执行'} · ${e.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: IosType.footnote,
                            color: p.label2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: p.label3,
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
    final p = IosPalette.of(context);
    final lines = unifiedDiff(change.oldText, change.newText);
    // 宽行不换行（换行会毁掉代码缩进和 diff 对齐），整块横向滚动；
    // 行宽按 monospace 字符数估算，超出估算的极长行截断显示。
    final rowWidth = _diffRowWidth(context, lines);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        0,
        IosTheme.spaceL,
        IosTheme.spaceM,
      ),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(IosTheme.radiusXS),
        border: Border.all(color: p.separator, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 内容比可视区窄时撑满可视区，色带不缩成一条
          final width = rowWidth < constraints.maxWidth
              ? constraints.maxWidth
              : rowWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in lines) _diffLine(l, p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 估算 diff 单行渲染宽度：monospace 字符宽 × 最长行字符数。
  /// Tab 按 4 个空格宽估算，再加 1 字符余量。
  double _diffRowWidth(BuildContext context, List<DiffLine> lines) {
    const style = TextStyle(fontFamily: 'monospace', fontSize: 12);
    final tp = TextPainter(
      text: const TextSpan(text: 'MMMMMMMMMM', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final charWidth = tp.maxIntrinsicWidth / 10;
    tp.dispose();
    var maxLen = 0;
    for (final l in lines) {
      final len = l.text.replaceAll('\t', '    ').length + 2; // +2 = 前缀
      if (len > maxLen) maxLen = len;
    }
    return (maxLen + 1) * charWidth + IosTheme.spaceM * 2;
  }

  Widget _diffLine(DiffLine l, IosPalette p) {
    Color? bg;
    Color? textColor;
    String prefix = '  ';
    switch (l.op) {
      case DiffOp.add:
        bg = p.okSoft;
        textColor = p.ok;
        prefix = '+ ';
        break;
      case DiffOp.del:
        bg = p.badSoft;
        textColor = p.bad;
        prefix = '- ';
        break;
      case DiffOp.same:
        textColor = p.label2;
        prefix = '  ';
        break;
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceM,
        vertical: IosTheme.spaceXXS,
      ),
      // 宽行单行显示（横向滚动由外层块负责）；maxLines:1 防止估算偏差
      // 导致意外折行破坏对齐
      child: SelectableText(
        '$prefix${l.text}',
        maxLines: 1,
        style: TextStyle(
          fontFamily: IosType.mono,
          fontSize: IosType.footnote,
          height: 1.4,
          color: textColor,
        ),
      ),
    );
  }
}
