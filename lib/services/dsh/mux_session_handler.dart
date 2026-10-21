part of 'mux_stream.dart';

/// 会话事件分发（MuxStream 的 part 文件）
///
/// 从 session/follow 的 journal event 中提取并分发到对应回调。
/// 独立文件以便维护，与 MuxStream 共享私有作用域。

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
      // 与 Web 端一致：只有 source.kind == user 才是真人输入；
      // runtime-context / skill-catalog / time-context 等注入上下文不上屏。
      if (!isHumanUserMessage(data) || !isAppendSurface(event)) break;
      final source = data['source'];
      final text = extractContentBlocks(data['content'], lastOnly: true);
      final rpcId = source['rpcId'] as String?;
      final messageId = data['id'] as String?;
      final seq = '${event['seq'] ?? ''}';
      if (text.isNotEmpty) {
        self.onUserMessage?.call(text, rpcId, seq, messageId);
      }
      break;
    case 'assistant/message':
      // 定稿：整条替换，并结束打字机态（避免与 assistant-stream 双份渲染）。
      // 带 tool-call 的消息是过程步骤，dispatcher 会丢弃当前过程气泡。
      if (!isAppendSurface(event)) break;
      final message = data['message'];
      final content = message is Map ? message['content'] : null;
      final text = extractAssistantReply(message);
      final hasToolCall = hasToolCallBlock(content);
      final interrupted = data['interrupted'] == true;
      self.onAssistantFinal
          ?.call(text, interrupted, hasToolCall: hasToolCall);
      break;
    case 'assistant/attempt':
      // 尝试记录只有 stream，没有可展示的 message；最终回答由
      // assistant/message 落盘，这里不再兜底，避免过程文本重复上屏。
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
