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

/// 从 turn/end 的 reason 字段提取错误信息（如有）
String? _extractTurnError(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final reason = data['reason'];
  if (reason is! Map<String, dynamic>) return null;
  if (reason['kind'] != 'error') return null;
  final error = reason['error'];
  if (error is Map<String, dynamic>) {
    return error['message'] as String? ?? '未知错误';
  }
  return '未知错误';
}

void _handleSessionEvent(
    MuxStream self,
    String type,
    Map<String, dynamic> event,
    Map<String, dynamic> data) {
  switch (type) {
    case 'user/message':
      final text = extractContentBlocks(data['content'], lastOnly: true);
      String? rpcId;
      final source = data['source'];
      if (source is Map<String, dynamic>) {
        rpcId = source['rpcId'] as String?;
      }
      final seq = '${event['seq'] ?? ''}';
      if (text.isNotEmpty) self.onUserMessage?.call(text, rpcId, seq);
      break;
    case 'assistant/message':
      // 定稿：整条替换，并结束打字机态（避免与 assistant-stream 双份渲染）
      final text = _extractAssistantText(data['message']);
      final interrupted = data['interrupted'] == true;
      self.onAssistantMessage?.call(text);
      self.onAssistantFinal?.call(text, interrupted);
      break;
    case 'assistant/attempt':
      // 未定稿的尝试记录：只在没有 assistant/message 时兜底
      final text = _extractAssistantText(data['message']);
      if (text.isNotEmpty) self.onAssistantMessage?.call(text);
      break;
    case 'turn/start':
      // 权威的「开始工作」信号：turn/end 置空闲后，新一轮由它重新武装，
      // 不依赖 api-session/status 是否恰好发生状态变化（它只在变化时推送）
      self.onTurnStart?.call();
      break;
    case 'tool/call':
      self.onToolCall?.call(
        data['name'] as String? ?? 'tool',
        data['arguments'] as String?,
      );
      break;
    case 'tool/result':
      self.onToolResult?.call();
      break;
    case 'turn/end':
      final turnError = _extractTurnError(data);
      if (turnError != null) {
        self.onSessionError?.call(self.sessionId ?? '', turnError);
      }
      self.onTurnEnd?.call();
      break;
  }
}
