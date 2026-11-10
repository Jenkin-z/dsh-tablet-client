part of 'event_dispatcher.dart';

// ── 过程步骤（event_process_steps.dart）─────────────────────
//
// Web 端把一个 turn 内的过程内容（工具调用前的过程文本、工具调用）
// 折叠进过程区：运行中实时展开，收尾后收起。这里维护同一份条目集，
// 并以一条哨兵消息（role: 'steps'）挂在消息流里当前回答之前，
// 由 ChatMessageList 渲染成过程步骤卡。
//
// 只依赖 core 的字段与方法（_deltaBuffer/_dropCurrentAssistant 等），
// 不跨 mixin 调用，保持各分片可独立替换。
// mixin 依赖字段声明在 [_EventDispatcherCore]（event_dispatcher.dart）。

/// 消息流里过程步骤卡的哨兵 id（role == 'steps'）
const String _processCardId = 'process-card';

mixin EventDispatcherProcess on _EventDispatcherCore {
  final List<ProcessEntry> _processEntries = [];
  bool _processCollapsed = false;

  /// 当前 turn 的过程条目（只读副本）
  List<ProcessEntry> get processEntries => List.unmodifiable(_processEntries);

  /// turn 是否已收尾（收起态）
  bool get processCollapsed => _processCollapsed;

  /// 固化过程文本：优先用定稿文本（DSH 的 assistant/message 带 tool-call
  /// 时，文本与 tool-call 同一条 durable 消息整段到达），否则取当前流式
  /// 气泡 + 未 flush 的增量。turn 已收尾后的迟到事件不进条目。
  void captureProcessText(String finalized) {
    if (_turnClosed) return;
    final pending = _deltaBuffer.toString();
    _clearDelta();
    var text = finalized;
    if (text.isEmpty) {
      final idx = _currentAssistantId == null
          ? -1
          : _messages.indexWhere((m) => m.id == _currentAssistantId);
      text = (idx >= 0 ? _messages[idx].content : '') + pending;
    }
    if (text.isEmpty) return;
    _processEntries.add(ProcessEntry.text(
      id: 'pt-${DateTime.now().microsecondsSinceEpoch}',
      text: text,
    ));
    _syncProcessCard();
    state.notify();
  }

  /// 工具调用到来：固化过程文本（若有）+ 追加 running 的工具条目
  void addProcessStep(String toolName, String? arguments) {
    if (_turnClosed) return;
    captureProcessText('');
    _dropCurrentAssistant();
    _processEntries.add(ProcessEntry.tool(
      id: 'pc-${DateTime.now().microsecondsSinceEpoch}',
      toolName: toolName,
      toolDetail: extractToolDetail(arguments),
    ));
    _syncProcessCard();
    // setActiveTool 同值不通知时（连续同名工具），条目更新也要有人看到
    state.notify();
  }

  /// 工具结果到达：收尾最后一个 running 条目
  void completeProcessTool(bool failed) {
    if (_turnClosed) return;
    final idx = _processEntries.lastIndexWhere((e) => e.isRunning);
    if (idx < 0) return;
    _processEntries[idx] = _processEntries[idx].copyWith(
      status: failed ? ProcessEntryStatus.failed : ProcessEntryStatus.done,
    );
    _syncProcessCard();
    state.notify();
  }

  /// turn 收尾：收起（条目保留，可展开回看，直到新一轮开始）
  void collapseProcess() {
    if (_processEntries.isEmpty) return;
    _processCollapsed = true;
    state.notify();
  }

  /// 新一轮开始：清空上一轮的过程条目
  void resetProcess() {
    if (_processEntries.isEmpty && !_processCollapsed) return;
    _processEntries.clear();
    _processCollapsed = false;
    _removeProcessCard();
    state.notify();
  }

  /// 历史装载 / 后端重置时静默清理（调用方另有广播，不再 notify）
  void clearProcessSilently() {
    _processEntries.clear();
    _processCollapsed = false;
    _removeProcessCard();
  }

  // ── 哨兵同步 ────────────────────────────────────

  /// 哨兵插在最后一条 assistant 消息之前（时间序：过程 < 回答）；
  /// 没有回答气泡时挂到列表尾（最新位置）。
  void _syncProcessCard() {
    _removeProcessCard();
    if (_processEntries.isEmpty) return;
    var idx = _messages.lastIndexWhere((m) => m.role == 'assistant');
    if (idx < 0) idx = _messages.length;
    _messages.insert(
      idx,
      ChatMessage(id: _processCardId, role: 'steps', content: ''),
    );
  }

  void _removeProcessCard() {
    _messages.removeWhere((m) => m.id == _processCardId);
  }
}
