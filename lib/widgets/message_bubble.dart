import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../theme/ios_theme.dart';

/// 单条消息气泡：用户消息纯文本，Agent 消息按 Markdown 渲染
///
/// iOS 风格：用户消息蓝色圆角气泡，Agent 消息白色/深色背景，
/// 系统消息（错误等）淡红背景居中显示。
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
    final theme = Theme.of(context);

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
              ? (isDark
                  ? IosTheme.iosRed.withValues(alpha: 0.15)
                  : IosTheme.iosRed.withValues(alpha: 0.08))
              : isUser
                  ? IosTheme.iosBlue
                  : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
          borderRadius: BorderRadius.circular(IosTheme.radiusM),
          border: isSystem
              ? Border.all(
                  color: IosTheme.iosRed.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSystem)
              SelectableText(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? IosTheme.iosRed.withValues(alpha: 0.9)
                      : IosTheme.iosRed,
                  height: 1.5,
                  fontSize: 14,
                ),
              )
            else if (isUser)
              SelectableText(
                message.content,
                style: theme.textTheme.bodyLarge?.copyWith(
                  // 未确认的乐观气泡先淡化，Host 回执后恢复实心
                  color: message.pending
                      ? Colors.white.withValues(alpha: 0.65)
                      : Colors.white,
                  height: 1.5,
                  fontSize: 16,
                ),
              )
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyLarge?.copyWith(
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    height: 1.5,
                    fontSize: 16,
                  ),
                  code: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: IosTheme.iosBlue,
                    backgroundColor: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(IosTheme.radiusXS),
                  ),
                  codeblockPadding: const EdgeInsets.all(IosTheme.spaceM),
                  tableBorder: TableBorder.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: IosTheme.iosBlue.withValues(alpha: 0.5),
                        width: 3,
                      ),
                    ),
                  ),
                  blockquotePadding: const EdgeInsets.only(
                    left: IosTheme.spaceM,
                    top: IosTheme.spaceXS,
                    bottom: IosTheme.spaceXS,
                  ),
                ),
              ),
            if (message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: IosTheme.spaceS),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isUser ? Colors.white : IosTheme.iosBlue,
                      ),
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    Text(
                      '正在输入…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isUser
                            ? Colors.white.withValues(alpha: 0.8)
                            : IosTheme.iosGray,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}