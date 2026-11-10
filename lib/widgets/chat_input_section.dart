import 'package:flutter/material.dart';
import '../models/queued_message.dart';
import 'chat_input_bar.dart';
import 'queue_banner.dart';

/// 对话页输入区：排队横幅 + 输入栏的组合
///
/// 从 chat_screen.dart 拆出来（Screen 文件 400 行上限）。
/// 「忙」的语义在这里升级：运行中**和排队中**都算忙 —— turn/end 到
/// turn/start 的间隙（队列非空时）停止按钮不得闪断成发送。
class ChatInputSection extends StatelessWidget {
  final TextEditingController controller;
  final bool connected;

  /// 忙 = 发送中 / 排队中 / 运行中（来自 SessionState.turn.busy）
  final bool busy;

  /// 当前会话的 Host 队列快照（空列表时不渲染横幅）
  final List<QueuedMessage> queue;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const ChatInputSection({
    super.key,
    required this.controller,
    required this.connected,
    required this.busy,
    required this.queue,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        QueueBanner(queue: queue),
        ChatInputBar(
          controller: controller,
          connected: connected,
          running: busy,
          onSend: onSend,
          onStop: onStop,
        ),
      ],
    );
  }
}
