part of 'mux_stream.dart';

/// 会话事件分发（MuxStream 的 part 文件）
///
/// 从 session/follow 的 journal event 中提取并分发到对应回调。
/// 独立文件以便维护，与 MuxStream 共享私有作用域。

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
      // 用户消息取全部 text 块（多块 '\n\n' 连接），与历史装载一致
      final text = extractContentBlocks(data['content']);
      final rpcId = source['rpcId'] as String?;
      final messageId = data['id'] as String?;
      final seq = '${event['seq'] ?? ''}';
      if (text.isNotEmpty) {
        self.onUserMessage?.call(text, rpcId, seq, messageId);
      }
      break;
    case 'assistant/message':
      // 定稿：整条替换，并结束打字机态（避免与 assistant-stream 双份渲染）。
      // 带 tool-call 的消息是过程步骤：文本整段交给 dispatcher 固化进
      // 过程步骤卡（Web 端折叠进过程区的做法），不再丢弃。
      if (!isAppendSurface(event)) break;
      final message = data['message'];
      final content = message is Map ? message['content'] : null;
      final hasToolCall = hasToolCallBlock(content);
      final text = hasToolCall
          ? extractAssistantText(message)
          : extractAssistantReply(message);
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
      // stopped（error.code == 'interrupted'）经 side-channel 传递：
      // onToolResult 的字段类型锁定为 void Function(bool)，见 mux_history.dart
      muxToolResultWasInterrupted = toolResultStopped(data);
      self.onToolResult?.call(toolResultFailed(data));
      break;
    case 'turn/end':
      // 先报错再收尾：错误上屏（onSessionError）不能被 turn 收尾闸门吞掉
      final turnError = extractTurnEndError(data);
      if (turnError != null) {
        self.onSessionError?.call(self.sessionId ?? '', turnError);
      }
      self.onTurnEnd?.call();
      break;
  }
}
