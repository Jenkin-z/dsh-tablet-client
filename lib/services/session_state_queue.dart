part of 'session_state.dart';

// Host 队列视图（SessionState 的 part 文件）
//
// 每会话一份队列快照（权威来自 DSH 的 `queue` control 帧与 baseline），
// UI 只渲染当前会话的；TurnSupervisor.turnEnd 用它判定落 queued 还是 idle。
// mixin 依赖字段声明在 [_SessionStateCore]。

mixin SessionStateQueue on _SessionStateCore {
  final Map<String, List<QueuedMessage>> _queues = {};

  /// 指定会话的队列快照（只读；无队列为空列表）
  List<QueuedMessage> queueFor(String? sessionId) =>
      sessionId == null || !_queues.containsKey(sessionId)
          ? const []
          : _queues[sessionId]!;

  /// 横幅计数：queued + steering（context 是上下文注入，不算用户排队）
  int queuedCountOf(String? sessionId) =>
      queueFor(sessionId).where((m) => m.countsAsUserQueue).length;

  /// Host 队列快照整体替换（按会话隔离，别的会话的队列不进当前视图）。
  /// 内容未变不广播（queue 帧可能高频重放同快照）。
  void replaceQueue(String sessionId, List<QueuedMessage> items) {
    final old = _queues[sessionId] ?? const [];
    if (_sameQueue(old, items)) return;
    if (items.isEmpty) {
      _queues.remove(sessionId);
    } else {
      _queues[sessionId] = List.unmodifiable(items);
    }
    notifyListeners();
  }

  static bool _sameQueue(List<QueuedMessage> a, List<QueuedMessage> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      // id/placement/content/rpcId 全比：edit/updateQueue 后 Host 推的
      // 快照只有内容变了（id 不变），漏比会导致横幅不刷新
      if (x.id != y.id || x.placement != y.placement) return false;
      if (x.rpcId != y.rpcId || x.content != y.content) return false;
    }
    return true;
  }
}
