part of 'event_dispatcher.dart';

// ── 流式增量与文本定稿（event_streaming_text.dart）────────────
//
// 只搬代码不改逻辑：delta 缓冲、迟到的 chunk 挡板、assistant 定稿。
// mixin 依赖字段声明在 [_EventDispatcherCore]（event_dispatcher.dart）。

mixin EventDispatcherStreaming on _EventDispatcherCore {
  /// 文本增量到达：缓冲 120ms 后统一 flush，减少 notify 频率。
  void onTextDelta(String delta) {
    // 不要在这里碰全局状态：chunk 是最高频的事件，任何 notify 都会让
    // 整个页面树跟着重绘。增量只进缓冲区，由消息版本号驱动局部刷新。
    _deltaBuffer.write(delta);
    _deltaFlushTimer ??= Timer(const Duration(milliseconds: 120), _flushDelta);
  }

  void _flushDelta() {
    _deltaFlushTimer = null;
    final text = _deltaBuffer.toString();
    _deltaBuffer.clear();
    if (text.isEmpty) return;

    state.setAssistantStreaming(true);
    // 只有「本轮还没结束」时才把运行态拉起来。
    // 否则一个迟到的 chunk（重连补发、乱序）会把 turn/end 刚置好的空闲
    // 又顶回「进行中」，而且之后不会再有 turn/end 来收尾 —— 按钮就永久卡住。
    if (!_turnClosed) state.setAgentRunning(true);

    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        content: _messages[idx].content + text,
      );
    } else {
      state.setActiveTool(null);
      _messages.add(ChatMessage(
        id: 'stream-${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: text,
        isStreaming: true,
      ));
    }
    _bumpMessages();
    onScrollToBottom?.call();
  }

  /// `assistant/message` 定稿后的收尾
  ///
  /// Web 端的防双渲染是「扣住再放行」：durable 消息先落到 pending，
  /// 等 assistant-stream 的 `end` 帧点名同一 seq 才发布。
  /// 这里用等价做法 —— 定稿即整体替换那条 streaming 气泡，并结束打字机态。
  ///
  /// [interrupted] 为真表示被停止，Web 端显示「已停止」而不是错误。
  void onAssistantFinal(String text, bool interrupted) {
    if (text.isEmpty) {
      // 空定稿：可能只是占位，别把已有内容抹掉
      state.setAssistantStreaming(false);
      return;
    }
    onAssistantMessage(text);
    state.setAssistantStreaming(false);
    if (interrupted) state.setLastTurnEnd(DateTime.now());
  }

  void onAssistantMessage(String text) {
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _deltaBuffer.clear();

    state.setAssistantStreaming(false);
    state.setActiveTool(null);

    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(content: text, isStreaming: false);
    } else {
      final lastAssistant = _messages.lastIndexWhere((m) => m.role == 'assistant');
      final existing = lastAssistant >= 0 ? _messages[lastAssistant].content : '';
      if (lastAssistant >= 0 &&
          (existing == text || (existing.isNotEmpty && text.startsWith(existing)))) {
        _messages[lastAssistant] = _messages[lastAssistant].copyWith(
          content: text,
          isStreaming: false,
        );
      } else {
        _messages.add(ChatMessage(
          id: 'a-${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: text,
        ));
      }
    }
    _bumpMessages();
    onScrollToBottom?.call();
  }
}
