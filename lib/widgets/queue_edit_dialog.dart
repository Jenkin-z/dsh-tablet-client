import 'package:flutter/material.dart';
import '../models/queued_message.dart';

/// 排队消息编辑弹窗（从 queue_banner.dart 拆出的子组件）
///
/// 预填条目原文，确认后返回新内容；取消 / 内容为空 / 内容未变都返回 null，
/// 由调用方决定是否发起 updateQueue edit。
Future<String?> showQueueEditDialog(
  BuildContext context,
  QueuedMessage item,
) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final field = TextEditingController(text: item.content);
      return AlertDialog(
        title: const Text('编辑排队消息'),
        content: TextField(
          controller: field,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, field.text.trim()),
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
}
