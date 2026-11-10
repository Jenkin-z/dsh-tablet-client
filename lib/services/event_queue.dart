part of 'event_dispatcher.dart';

// ── Host 队列（event_queue.dart）────────────────────────────
//
// DSH 的 `session/prompt` 以 mode:'queue' 发送：任务运行中用户继续输入
// 时消息进 Host 队列，当前轮结束后 Host 自动开跑下一轮。队列快照来自
// `session/control` 的 `queue` 帧（{type, sessionId, items}）与
// `baseline`（{queues: {sessionId: [...]}}），形状见 docs/MUX_PROTOCOL.md。
//
// 职责：
// 1. 解析并按会话隔离地更新队列视图（SessionStateQueue）；
// 2. rpcId 对账：快照里有本会话乐观气泡的 rpcId = Host 已受理，
//    乐观气泡就地转确认态（与 durable 对账双保险，谁先到谁生效）；
// 3. 轮次相位联动：本轮已收尾（turnClosed）而队列非空 → queued 相位
//    （busy 延续，停止按钮不闪断）；队列清空而无新轮 → 回 idle。
// mixin 依赖字段声明在 [_EventDispatcherCore]（event_dispatcher.dart）。

mixin EventDispatcherQueue on _EventDispatcherCore {
  /// `session/control` 的 `queue` 帧：某会话的完整队列快照（整体替换）
  void onQueueUpdate(String sessionId, List<Map<String, dynamic>> items) {
    final parsed = parseQueuedItems(items);
    final isCurrent = sessionId == state.sessionId;
    if (isCurrent) {
      // Host 受理 = 乐观气泡的可视确认（「发出去了，在排队」）
      for (final q in parsed) {
        final rid = q.rpcId;
        if (rid != null && rid.isNotEmpty) confirmLocalUserMessage(rid);
      }
    }
    // 先落队列视图：supervisor 的队列判定（hasQueuedWork）读的是它
    state.replaceQueue(sessionId, parsed);
    if (isCurrent) {
      if (parsed.any((m) => m.countsAsUserQueue)) {
        // 本轮已收尾而队列还有活：busy 以 queued 相位延续
        if (_turnClosed) supervisor.queuePending();
      } else {
        // 队列被清空（Host 消化/撤走）而 turn/start 未到：queued 退回 idle
        supervisor.queueDrained();
      }
    }
  }

  /// `control/baseline`：重连时恢复所有会话的队列视图
  ///
  /// baseline 形如 `{queues: {sessionId: [...]}, jobs, projections}`；
  /// 只消费 queues，jobs/投影仍由各自的既有通道负责。
  void onControlBaseline(Map<String, dynamic> baseline) {
    final value = baseline['value'];
    final raw = value is Map<String, dynamic> ? value : baseline;
    final queues = raw['queues'];
    if (queues is! Map) return;
    queues.forEach((sid, items) {
      if (sid is! String || sid.isEmpty) return;
      if (items is! List) return;
      onQueueUpdate(
        sid,
        items.whereType<Map<String, dynamic>>().toList(),
      );
    });
  }
}
