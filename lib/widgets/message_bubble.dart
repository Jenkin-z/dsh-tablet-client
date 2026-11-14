import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/ios_theme.dart';
import 'message_markdown.dart';
import 'adaptive_selectable_text.dart';
import 'streaming_caret.dart';

/// 单条消息气泡（DESIGN.md §6）
///
/// 用户气泡 = accent 填充右对齐；Agent 气泡 = surface-2 左对齐；
/// system 消息（错误）= bad 软底卡，错误是真实信息不是装饰。
class MessageBubble extends StatefulWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  ChatMessage? _cachedMessage;
  ({bool dark, double width, TextScaler scaler})? _cachedLayout;
  Widget? _cachedWidget;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layout = (
      dark: isDark,
      width: MediaQuery.sizeOf(context).width,
      scaler: MediaQuery.textScalerOf(context),
    );

    // 已定稿消息的实例不会再变。父级因为其它消息/运行态重建时直接复用
    // 整棵子树，Markdown 不重新解析，文本选择状态也不会丢。
    if (identical(widget.message, _cachedMessage) &&
        layout == _cachedLayout &&
        _cachedWidget != null) {
      return _cachedWidget!;
    }

    final built = _buildBubble(context, isDark: isDark);
    _cachedMessage = widget.message;
    _cachedLayout = layout;
    _cachedWidget = built;
    return built;
  }

  Widget _buildBubble(BuildContext context, {required bool isDark}) {
    final message = widget.message;
    final isUser = message.role == 'user';
    final isSystem = message.role == 'system';
    final p = IosPalette.ofBrightness(isDark ? Brightness.dark : Brightness.light);

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : isSystem
              ? Alignment.center
              : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          top: IosTheme.spaceXS,
          bottom: IosTheme.spaceXS,
          left: isUser ? IosTheme.spaceXXXL : IosTheme.spaceS,
          right: isUser ? IosTheme.spaceS : IosTheme.spaceXXXL,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: IosTheme.spaceM,
          horizontal: IosTheme.spaceL,
        ),
        decoration: BoxDecoration(
          color: isSystem
              ? p.badSoft
              : isUser
                  ? p.accent
                  : p.surface2,
          borderRadius: BorderRadius.circular(IosTheme.radiusS),
          border: isSystem
              ? Border.all(color: p.bad.withValues(alpha: 0.3), width: 0.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSystem)
              _systemContent(context, message, p)
            else if (isUser)
              AdaptiveSelectableText(
                message.content,
                style: TextStyle(
                  // 未确认的乐观气泡先淡化，Host 回执后恢复实心
                  color: message.pending
                      ? p.onAccent.withValues(alpha: 0.65)
                      : p.onAccent,
                  height: 1.5,
                  fontSize: IosType.body,
                ),
              )
            else
              MessageMarkdown(data: message.content),
            if (message.isStreaming) _streamingFooter(context, isUser, p),
          ],
        ),
      ),
    );
  }

  /// 错误卡内容：图标 + 单行标签 + 错误正文
  Widget _systemContent(BuildContext context, ChatMessage message, IosPalette p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: p.bad),
        const SizedBox(width: IosTheme.spaceS),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '出错了',
                style: TextStyle(
                  color: p.bad,
                  fontSize: IosType.footnotePlus,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              AdaptiveSelectableText(
                message.content,
                style: TextStyle(
                  color: p.bad.withValues(alpha: 0.85),
                  height: 1.5,
                  fontSize: IosType.footnotePlus,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 流式脚注：Agent 用光标（§7），用户乐观气泡不显示
  Widget _streamingFooter(BuildContext context, bool isUser, IosPalette p) {
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: IosTheme.spaceXS),
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: p.onAccent.withValues(alpha: 0.8),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamingCaret(color: p.accent),
          const SizedBox(width: IosTheme.spaceS),
          Text(
            '正在输入',
            style: TextStyle(color: p.label3, fontSize: IosType.caption),
          ),
        ],
      ),
    );
  }
}
