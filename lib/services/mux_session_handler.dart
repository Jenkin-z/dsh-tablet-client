part of 'mux_stream.dart';

/// 会话事件分发（MuxStream 的 part 文件）
///
/// 从 session/follow 的 journal event 中提取并分发到对应回调。
/// 独立文件以便维护，与 MuxStream 共享私有作用域。

/// 从 assistant/message 的 message 字段提取纯文本
String _extractAssistantText(dynamic message) {
  if (message is! Map<String, dynamic>) return '';
  return extractContentBlocks(message['content']);
}

void _handleSessionEvent(
    MuxStream self,
    String type,
    Map<String, dynamic> event,
    Map<String, dynamic> data) {
  switch (type) {
    case 'user/message':
      final text = extractContentBlocks(data['content']);
      String? rpcId;
      final source = data['source'];
      if (source is Map<String, dynamic>) {
        rpcId = source['rpcId'] as String?;
      }
      final seq = '${event['seq'] ?? ''}';
      if (text.isNotEmpty) self.onUserMessage?.call(text, rpcId, seq);
      break;
    case 'assistant/chunk':
      final chunk = data['chunk'];
      if (chunk is Map<String, dynamic> && chunk['type'] == 'text-delta') {
        final text = chunk['text'] as String? ?? '';
        if (text.isNotEmpty) self.onTextDelta?.call(text);
      }
      break;
    case 'assistant/message':
      final text = _extractAssistantText(data['message']);
      if (text.isNotEmpty) self.onAssistantMessage?.call(text);
      break;
    case 'tool/call':
      self.onToolCall?.call(data['name'] as String? ?? 'tool');
      break;
    case 'tool/result':
      self.onToolResult?.call();
      break;
    case 'turn/end':
      self.onTurnEnd?.call();
      break;
  }
}
