import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 对话页底部输入栏 —— iOS 风格
///
/// 圆角输入框 + 蓝色发送按钮，类似 iMessage 输入栏。
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool connected;
  final bool sending;
  final VoidCallback onSend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.connected,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          IosTheme.spaceL,
          IosTheme.spaceS,
          IosTheme.spaceL,
          IosTheme.spaceS,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE5E5EA),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: controller,
                  enabled: connected,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  ),
                  decoration: InputDecoration(
                    hintText: '输入消息…',
                    hintStyle: TextStyle(
                      color: IosTheme.iosGray,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: IosTheme.spaceL,
                      vertical: IosTheme.spaceS,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: IosTheme.spaceS),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (connected && !sending)
                    ? IosTheme.iosBlue
                    : IosTheme.iosGray3,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                        size: 20,
                      ),
                onPressed: (connected && !sending) ? onSend : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
