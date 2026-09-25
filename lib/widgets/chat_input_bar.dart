import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 对话页底部输入栏 —— iOS 风格
///
/// 「发送 / 停止」的取舍与 Web 端一致（InputBar.tsx:283）：
/// · 运行中 且 输入框为空 → 主按钮为「停止」
/// · 运行中 但 有草稿文字  → 主按钮仍为「发送」（可排队/插话），
///   此时在旁边单独给出一个「停止」，两者不互相顶掉
/// · 未运行 → 主按钮为「发送」
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool connected;
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.connected,
    required this.running,
    required this.onSend,
    required this.onStop,
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
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasDraft = value.text.trim().isNotEmpty;
            // 有草稿时发送优先，停止另置于左侧
            final primaryIsStop = running && !hasDraft;
            final showSecondaryStop = running && hasDraft;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showSecondaryStop) ...[
                  _stopButton(filled: false),
                  const SizedBox(width: IosTheme.spaceS),
                ],
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
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                      decoration: InputDecoration(
                        hintText: connected ? '输入消息…' : '未连接，文字会保留',
                        hintStyle: const TextStyle(
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
                if (primaryIsStop)
                  _stopButton(filled: true)
                else
                  _sendButton(hasDraft),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sendButton(bool hasDraft) {
    final enabled = connected && hasDraft;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: enabled ? IosTheme.iosBlue : IosTheme.iosGray3,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
        onPressed: enabled ? onSend : null,
      ),
    );
  }

  Widget _stopButton({required bool filled}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: filled ? IosTheme.iosRed : Colors.transparent,
        shape: BoxShape.circle,
        border: filled
            ? null
            : Border.all(color: IosTheme.iosRed, width: 1.5),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: '停止',
        icon: Icon(
          Icons.stop_rounded,
          color: filled ? Colors.white : IosTheme.iosRed,
          size: 20,
        ),
        onPressed: onStop,
      ),
    );
  }
}
