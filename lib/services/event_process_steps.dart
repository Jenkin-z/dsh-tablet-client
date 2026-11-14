part of 'event_dispatcher.dart';

// ── 过程步骤（event_process_steps.dart）─────────────────────
//
// 过程内容（reasoning、工具、工具前的文本）折叠进过程区，以哨兵
// 消息（role: 'steps'）挂在当前回答之前，运行中展开，收尾后收起。
// on 约束含 Streaming/TurnSession/Messages：各钩子沿 mixin 应用链调
// super（onTextDelta 分流、onAssistantFinal 落定 stopped 等）。

/// 消息流里过程步骤卡的哨兵 id（role == 'steps'）
const String _processCardId = 'process-card';

mixin EventDispatcherProcess on _EventDispatcherCore, EventDispatcherStreaming,
    EventDispatcherTurnSession, EventDispatcherMessages {
  final List<ProcessEntry> _processEntries = [];
  bool _processCollapsed = false;

  /// reasoning 增量缓冲（与文本增量同样合帧，减少 notify 频率）
  final StringBuffer _reasoningBuffer = StringBuffer();
  Timer? _reasoningFlushTimer;

  /// 当前 turn 的过程条目（只读副本）
  List<ProcessEntry> get processEntries => List.unmodifiable(_processEntries);

  /// turn 是否已收尾（收起态）
  bool get processCollapsed => _processCollapsed;

  /// mux 文本增量入口：side-channel 标记为 reasoning 时分流进过程条目。
  @override
  void onTextDelta(String delta) {
    final isReasoning = muxNextTextDeltaIsReasoning;
    muxNextTextDeltaIsReasoning = false;
    if (isReasoning) {
      if (_turnClosed) return;
      _reasoningBuffer.write(delta);
      _reasoningFlushTimer ??=
          Timer(const Duration(milliseconds: 120), _flushReasoning);
      return;
    }
    _settleRunningReasoning(); // 文本阶段开始：「思考中」落定
    super.onTextDelta(delta);
  }

  void _flushReasoning() {
    _reasoningFlushTimer = null;
    final text = _reasoningBuffer.toString();
    _reasoningBuffer.clear();
    if (text.isEmpty || _turnClosed) return;
    _appendReasoningText(text);
  }

  void _appendReasoningText(String text) {
    final idx = _processEntries
        .lastIndexWhere((e) => e.kind == ProcessEntryKind.reasoning);
    if (idx >= 0) {
      _processEntries[idx] = _processEntries[idx]
          .copyWith(text: _processEntries[idx].text + text);
    } else {
      _processEntries.add(ProcessEntry.reasoning(
          id: 'pr-${DateTime.now().microsecondsSinceEpoch}', text: text));
    }
    _syncProcessCard();
    state.notify();
  }

  /// 「思考中」条目落定（文本开始/工具/定稿/收尾）；未 flush 增量就地固化。
  void _settleRunningReasoning() {
    _reasoningFlushTimer?.cancel();
    _reasoningFlushTimer = null;
    final pending = _reasoningBuffer.toString();
    _reasoningBuffer.clear();
    if (pending.isNotEmpty && !_turnClosed) _appendReasoningText(pending);
    final idx = _processEntries.lastIndexWhere(
        (e) => e.kind == ProcessEntryKind.reasoning && e.isRunning);
    if (idx < 0) return;
    _processEntries[idx] =
        _processEntries[idx].copyWith(status: ProcessEntryStatus.done);
    _syncProcessCard();
    state.notify();
  }

  /// 新一代尝试开始：上一代的 reasoning 条目随之退场（换型重起）
  @override
  void onAssistantStreamStart() {
    _cancelReasoningFlush();
    final before = _processEntries.length;
    _processEntries.removeWhere((e) => e.kind == ProcessEntryKind.reasoning);
    if (_processEntries.length != before) _syncProcessCard();
    super.onAssistantStreamStart();
  }

  /// 固化过程文本：定稿文本优先，否则取流式气泡 + 未 flush 增量。
  @override
  void captureProcessText(String finalized) {
    if (_turnClosed) return;
    final pending = _deltaBuffer.toString();
    _clearDelta();
    var text = finalized;
    if (text.isEmpty) {
      final i = _messages.indexWhere((m) => m.id == _currentAssistantId);
      text = (i >= 0 ? _messages[i].content : '') + pending;
    }
    if (text.isEmpty) return;
    _processEntries.add(ProcessEntry.text(
        id: 'pt-${DateTime.now().microsecondsSinceEpoch}', text: text));
    _syncProcessCard();
    state.notify();
  }

  /// 工具调用到来：固化过程文本（若有）+ 追加 running 的工具条目
  @override
  void addProcessStep(String toolName, String? arguments) {
    if (_turnClosed) return;
    captureProcessText('');
    _dropCurrentAssistant();
    _processEntries.add(ProcessEntry.tool(
        id: 'pc-${DateTime.now().microsecondsSinceEpoch}',
        toolName: toolName,
        toolDetail: extractToolDetail(arguments)));
    _syncProcessCard();
    // setActiveTool 同值不通知时（连续同名工具），条目更新也要有人看到
    state.notify();
  }

  /// 工具结果收尾最后一个 running 的 tool 条目。stopped 经 side-channel
  /// 传递（mux_history.dart），优先级高于 failed（Web §9.1）。
  @override
  void completeProcessTool(bool failed) {
    final interrupted = muxToolResultWasInterrupted;
    muxToolResultWasInterrupted = false;
    if (_turnClosed) return;
    final idx = _processEntries.lastIndexWhere(
        (e) => e.kind == ProcessEntryKind.tool && e.isRunning);
    if (idx < 0) return;
    _processEntries[idx] = _processEntries[idx].copyWith(
        status: interrupted
            ? ProcessEntryStatus.stopped
            : (failed ? ProcessEntryStatus.failed : ProcessEntryStatus.done));
    _syncProcessCard();
    state.notify();
  }

  /// 回合被用户停止：仍在跑的工具条目落定为 stopped（Web §9.2），
  /// tool/result 丢失（事件全被掐断）时的兜底。
  void _stopRunningTools() {
    var changed = false;
    for (var i = 0; i < _processEntries.length; i++) {
      final e = _processEntries[i];
      if (e.kind == ProcessEntryKind.tool && e.isRunning) {
        _processEntries[i] = e.copyWith(status: ProcessEntryStatus.stopped);
        changed = true;
      }
    }
    if (changed) {
      _syncProcessCard();
      state.notify();
    }
  }

  /// assistant 定稿：思考条目落定；被停止的回合把仍在跑的工具落定 stopped
  @override
  void onAssistantFinal(String text, bool interrupted,
      {bool hasToolCall = false}) {
    super.onAssistantFinal(text, interrupted, hasToolCall: hasToolCall);
    _settleRunningReasoning();
    if (interrupted) _stopRunningTools();
  }

  /// 工具调用：思考阶段结束
  @override
  void onToolCall(String toolName, [String? arguments]) {
    _settleRunningReasoning();
    super.onToolCall(toolName, arguments);
  }

  /// turn 收尾：思考条目落定
  @override
  void onTurnEnd() {
    super.onTurnEnd();
    _settleRunningReasoning();
  }

  /// 历史装载恢复最后一个 turn 的过程条目（工具卡，durable 的过程区）。
  /// 有 running 条目说明回合未收尾（重连半程），卡保持展开。
  void restoreProcessFromHistory(List<ProcessEntry> entries) {
    clearProcessSilently();
    if (entries.isEmpty) return;
    _processEntries.addAll(entries);
    _processCollapsed = !_processEntries.any((e) => e.isRunning);
    _syncProcessCard();
    state.notify();
    _bumpMessages();
  }

  /// 历史装载在消息分片（会清过程状态）之后补过程条目
  @override
  void onSnapshot(List<Map<String, dynamic>> records) {
    super.onSnapshot(records);
    restoreProcessFromHistory(parseHistoryProcess(records));
  }

  /// turn 收尾：收起（条目保留，可展开回看，直到新一轮开始）
  @override
  void collapseProcess() {
    if (_processEntries.isEmpty) return;
    _processCollapsed = true;
    state.notify();
  }

  /// 新一轮开始：清空上一轮的过程条目
  @override
  void resetProcess() {
    _cancelReasoningFlush();
    if (_processEntries.isEmpty && !_processCollapsed) return;
    _processEntries.clear();
    _processCollapsed = false;
    _removeProcessCard();
    state.notify();
  }

  /// 历史装载 / 后端重置时静默清理（调用方另有广播，不再 notify）
  @override
  void clearProcessSilently() {
    _cancelReasoningFlush();
    _processEntries.clear();
    _processCollapsed = false;
    _removeProcessCard();
  }

  void _cancelReasoningFlush() {
    _reasoningFlushTimer?.cancel();
    _reasoningFlushTimer = null;
    _reasoningBuffer.clear();
  }

  /// 哨兵插在最后一条 assistant 消息之前（时间序：过程 < 回答）；
  /// 没有回答气泡时挂到列表尾（最新位置）。
  void _syncProcessCard() {
    _removeProcessCard();
    if (_processEntries.isEmpty) return;
    var idx = _messages.lastIndexWhere((m) => m.role == 'assistant');
    if (idx < 0) idx = _messages.length;
    _messages.insert(idx,
        ChatMessage(id: _processCardId, role: 'steps', content: ''));
  }

  void _removeProcessCard() {
    _messages.removeWhere((m) => m.id == _processCardId);
  }
}
