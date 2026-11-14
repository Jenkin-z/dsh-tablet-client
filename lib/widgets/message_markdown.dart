import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/ios_theme.dart';

/// Agent 消息的 Markdown 渲染（DESIGN.md §4/§5：等宽只用于代码与数据，
/// 禁用 >1px 彩色左边框 —— 引用块改用 fill 软底）
class MessageMarkdown extends StatelessWidget {
  final String data;

  const MessageMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return MarkdownBody(
      data: data,
      selectable: !kIsWeb, // web 上 selectable 会让语义树丢失文本
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(
          color: p.label,
          height: 1.5,
          fontSize: IosType.body,
        ),
        h1: TextStyle(
          color: p.label,
          fontSize: IosType.title2,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        h2: TextStyle(
          color: p.label,
          fontSize: IosType.callout,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        h3: TextStyle(
          color: p.label,
          fontSize: IosType.body,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        listBullet: TextStyle(color: p.label, fontSize: IosType.body, height: 1.5),
        code: TextStyle(
          fontFamily: IosType.mono,
          fontSize: IosType.footnotePlus,
          color: p.accent,
          backgroundColor: p.fill,
        ),
        codeblockDecoration: BoxDecoration(
          color: p.fill,
          borderRadius: BorderRadius.circular(IosTheme.radiusS),
        ),
        codeblockPadding: const EdgeInsets.all(IosTheme.spaceM),
        tableBorder: TableBorder.all(color: p.separator, width: 0.5),
        blockquoteDecoration: BoxDecoration(
          color: p.fill,
          borderRadius: BorderRadius.circular(IosTheme.radiusXS),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceM,
          vertical: IosTheme.spaceXS,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.separator, width: 0.5)),
        ),
      ),
    );
  }
}
