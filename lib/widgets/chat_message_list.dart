import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/ios_theme.dart';
import 'message_bubble.dart';

/// 聊天消息列表：倒序 ListView，空会话显示占位文案
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.scrollController,
    required this.messages,
  });

  final ScrollController scrollController;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          '暂无消息',
          style: TextStyle(
            color: IosTheme.iosGray,
            fontSize: 15,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: IosTheme.spaceS),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        // key 必须跟消息走：插入/删除时按 index 复用 State 会让气泡内容错位，
        // 也会让 MessageBubble 的缓存命中到错误的消息上。
        return MessageBubble(key: ValueKey(message.id), message: message);
      },
    );
  }
}
