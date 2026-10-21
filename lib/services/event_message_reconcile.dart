part of 'event_dispatcher.dart';

// ── 消息装载 / 本地乐观气泡对账（event_message_reconcile.dart）────
//
// 只搬代码不改逻辑：乐观气泡生命周期、历史装载、user/durable 消息对账。
// mixin 依赖字段声明在 [_EventDispatcherCore]（event_dispatcher.dart）。

mixin EventDispatcherMessages on _EventDispatcherCore {
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// 本地立刻上屏一条用户气泡（发送后不等后端回显）
  void addLocalUserMessage(String text, String rpcId) {
    _pendingEcho[rpcId] = text;
    _messages.add(ChatMessage(
      id: rpcId,
      role: 'user',
      content: text,
      pending: true,
      rpcId: rpcId,
    ));
    _bumpMessages();
    onScrollToBottom?.call();
  }

  /// 发送失败：把乐观气泡撤掉
  void failLocalUserMessage(String rpcId) {
    if (_pendingEcho.remove(rpcId) == null) return;
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == rpcId && m.pending);
    if (_messages.length != before) _bumpMessages();
  }

  /// 发送成功确认：把乐观气泡就地转为确认态。
  ///
  /// opencode 的 durable 消息不带 rpcId，无法按 id 对账；
  /// POST /prompt 返回 2xx 即服务端已收，此时就地确认即可
  /// （DSH 仍走 [_reconcileEcho] 的 durable 对账，两条路并存）。
  void confirmLocalUserMessage(String rpcId) {
    if (!_pendingEcho.containsKey(rpcId)) return;
    _pendingEcho.remove(rpcId);
    final idx = _messages.indexWhere((m) => m.id == rpcId && m.pending);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(pending: false);
      _bumpMessages();
    }
  }

  /// 用 durable 消息替换乐观气泡（同一 rpcId 只保留一条，最终态为准）
  void _reconcileEcho(String? rpcId, String text) {
    if (rpcId == null || rpcId.isEmpty) return;
    if (_pendingEcho.remove(rpcId) == null) return;
    // 本地乐观气泡按 id 命中；如果快照已经先装入了 durable 消息，
    // 则按 rpcId 命中那条，避免重复。
    final idx = _messages.indexWhere(
      (m) => m.role == 'user' && (m.id == rpcId || m.rpcId == rpcId),
    );
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        content: text,
        pending: false,
        rpcId: rpcId,
      );
    }
  }

  /// 历史装载的公共段：DSH 的 onSnapshot 与 opencode 的 onHistoryLoaded
  /// 共用（重连瞬间自己刚发的消息不能凭空消失，两条路都必须补回未确认回显）。
  void _loadMessages(List<ChatMessage> loaded) {
    _messages.clear();
    _seenUserSeq.clear();
    _seenUserIds.clear();
    _currentAssistantId = null;
    _messages.addAll(loaded);
    // 快照里没出现、但仍未确认的本地回显要补回去，
    // 否则重连瞬间自己刚发的消息会凭空消失。
    // 已经以 rpcId 出现在快照里的则不再补，避免同一条消息显示两遍。
    final loadedRpcIds = <String>{
      for (final m in loaded)
        if (m.role == 'user' && m.rpcId != null && m.rpcId!.isNotEmpty)
          m.rpcId!,
    };
    for (final entry in _pendingEcho.entries) {
      if (loadedRpcIds.contains(entry.key)) continue;
      _messages.add(ChatMessage(
        id: entry.key,
        role: 'user',
        content: entry.value,
        pending: true,
        rpcId: entry.key,
      ));
    }
    state.clearChanges();
    _bumpMessages();
    onJumpToLatest?.call();
  }

  void onSnapshot(List<Map<String, dynamic>> records) {
    final parsed = parseHistory(records);
    _loadMessages(parsed
        .map((p) => ChatMessage(
              id: p.id,
              role: p.role,
              content: p.text,
              rpcId: p.rpcId,
            ))
        .toList());
    for (final v in parseHistoryViews(records)) {
      state.applyToolView(
        diffs: v.diffs,
        title: v.title,
        done: v.done,
        turn: v.turn,
      );
    }
  }

  /// 历史装载统一入口（opencode 走这条；消息已由 opencode_mapper 转成
  /// [ChatMessage]，装载/对账逻辑与 DSH 的 onSnapshot 完全同一段）。
  void onHistoryLoaded(List<ChatMessage> messages) => _loadMessages(messages);

  void onUserMessage(
    String text,
    String? rpcId,
    String seq, [
    String? messageId,
  ]) {
    // durable 消息 id 去重：同一条消息的 append/replacement 副本
    // 可能带不同 seq，但 data.id 相同，不能再多出一条用户气泡。
    final durableId = messageId;
    if (durableId != null &&
        durableId.isNotEmpty &&
        !_seenUserIds.add(durableId)) {
      return;
    }

    // 先按 rpcId 对账：本地乐观气泡就地转为确认态，不新增第二条
    if (rpcId != null && _pendingEcho.containsKey(rpcId)) {
      _reconcileEcho(rpcId, text);
      final key = 'u$seq';
      if (seq.isNotEmpty) _seenUserSeq.add(key);
      // 回显对账同样是新一轮开始：不重新武装的话，turn/end 之后用户
      // 马上再发一条，紧随其后的 running:true 会被 _turnClosed 挡掉。
      _turnClosed = false;
      _bumpMessages();
      return;
    }

    final key = 'u$seq';
    if (seq.isNotEmpty && !_seenUserSeq.add(key)) return;

    // 内容去重：如果最后一条用户消息内容相同，跳过（旧数据没有 data.id 时兜底）
    if (_messages.isNotEmpty &&
        _messages.last.role == 'user' &&
        _messages.last.content == text) {
      return;
    }

    // 用户发了新消息 = 新一轮的开始。
    // 必须在这里重新武装运行态：本轮消息可能被客户端去重（同内容、
    // 同 seq）而跳过下面那行，但用户的心智模型是「我一发，它就又在跑了」。
    _turnClosed = false;
    _messages.add(ChatMessage(
      id: key.isEmpty ? 'u-${DateTime.now().millisecondsSinceEpoch}' : key,
      role: 'user',
      content: text,
      rpcId: rpcId,
    ));
    _bumpMessages();
    onScrollToBottom?.call();
  }
}
