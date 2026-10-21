part of 'mux_stream.dart';

// session/follow 流 + workspace/follow 流（MuxStream 的 part 文件）
//
// journal 事件帧的回调分发在 mux_session_handler.dart（part 文件）。

extension on MuxStream {
  void _handleFollow(Map<String, dynamic> value) {
    switch (value['type'] as String? ?? '') {
      case 'snapshot':
        lastCursor = (value['cursor'] as num?)?.toInt();
        snapshotHasMore = value['hasMore'] == true;

        // 会话元数据投影：标题等实时信息来源于此
        final projections = value['projections'];
        if (projections is Map<String, dynamic>) {
          onProjections?.call(projections);
        }

        final records = (value['records'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        onSnapshot?.call(records);

        // 重连时正在进行的助手流基线：不消费会丢字
        final baseline = value['assistantStream'];
        if (baseline is Map<String, dynamic>) {
          _adoptAssistantBaseline(baseline);
        }
        break;
      case 'event':
        _onJournalEvent(value['event']);
        break;
      case 'assistant-stream':
        _onAssistantFrame(value['frame']);
        break;
    }
  }

  /// 采纳开窗的助手流基线：把已累积的片段补回界面，并重置 chunk 序号
  void _adoptAssistantBaseline(Map<String, dynamic> baseline) {
    _assistantRevision = (baseline['revision'] as num?)?.toInt();
    final attempt = baseline['activeAttempt'];
    if (attempt is! Map<String, dynamic>) {
      // 没有进行中的尝试 → 清空序号，避免用旧序号丢弃新 chunk
      _lastChunkIndex = null;
      return;
    }
    _lastChunkIndex = (attempt['nextIndex'] as num?)?.toInt();
    final stream = attempt['stream'];
    if (stream is List) {
      final text = StringBuffer();
      for (final item in stream) {
        if (item is Map<String, dynamic> && item['type'] == 'text-delta') {
          text.write(item['text'] as String? ?? '');
        }
      }
      if (text.isNotEmpty) onTextDelta?.call(text.toString());
    }
  }

  void _handleWorkspaceFollow(Map<String, dynamic> value) {
    List<String>? ids;
    switch (value['type'] as String? ?? '') {
      case 'baseline':
        // baseline: value.value.archivedSessionIds
        final inner = value['value'];
        if (inner is Map<String, dynamic>) {
          ids = (inner['archivedSessionIds'] as List?)
              ?.whereType<String>()
              .toList();
        }
        break;
      case 'archived':
        ids = (value['archivedSessionIds'] as List?)
            ?.whereType<String>()
            .toList();
        break;
    }
    if (ids != null) onWorkspaceBaseline?.call(ids);
  }

  /// journal 事件帧：`{ type:'event', event:{ type, seq, time, data } }`
  void _onJournalEvent(dynamic eventDyn) {
    if (eventDyn is! Map<String, dynamic>) return;
    final type = eventDyn['type'] as String? ?? '';
    final data = eventDyn['data'];

    // diff 只来自 tool/result.data.meta.diffs（线上没有 view 字段）
    final rec = parseDiffView(eventType: type, data: data);
    if (rec != null) onToolView?.call(rec);

    if (data is! Map<String, dynamic>) {
      if (type == 'turn/end') onTurnEnd?.call();
      return;
    }
    _handleSessionEvent(this, type, eventDyn, data);
  }

  /// 打字机帧：`{ type:'assistant-stream', frame }`
  ///
  /// frame.type 为 `start` / `chunk` / `end`。
  /// `chunk` 帧带稠密 `index`，用它可以丢弃乱序与重复的增量 —— 这是
  /// `assistant-stream` 与 journal `assistant/chunk` 双路喂入时唯一可靠的去重依据。
  void _onAssistantFrame(dynamic frameDyn) {
    if (frameDyn is! Map<String, dynamic>) return;

    switch (frameDyn['type'] as String? ?? '') {
      case 'start':
        _assistantRevision = (frameDyn['revision'] as num?)?.toInt();
        _lastChunkIndex = null;
        break;

      case 'chunk':
        final revision = (frameDyn['revision'] as num?)?.toInt();
        // revision 变化说明进入了新的一代，重置序号
        if (revision != null &&
            _assistantRevision != null &&
            revision != _assistantRevision) {
          _assistantRevision = revision;
          _lastChunkIndex = null;
        } else if (revision != null) {
          _assistantRevision = revision;
        }

        final index = (frameDyn['index'] as num?)?.toInt();
        if (index != null) {
          final last = _lastChunkIndex;
          // 只接受严格递增的序号（重复或倒序一律丢弃）
          if (last != null && index <= last) return;
          _lastChunkIndex = index;
        }

        final chunk = frameDyn['chunk'];
        if (chunk is Map<String, dynamic> && chunk['type'] == 'text-delta') {
          final text = chunk['text'] as String? ?? '';
          if (text.isNotEmpty) onTextDelta?.call(text);
        }
        break;

      case 'end':
        // 一次尝试结束：不在此处落最终消息，交给 journal 的
        // assistant/message 事件，避免同一段文本出现两条气泡。
        _lastChunkIndex = null;
        break;
    }
  }
}
