/// Host 队列条目模型（DSH `session/control` 的 `queue` 帧与 baseline）
///
/// 协议形状（docs/MUX_PROTOCOL.md:272）：
/// `SessionQueuedItem: { id, placement:'queued'|'steering'|'context', rpcId?, message:{ id, content } }`
///
/// - `queued`：排在当前轮之后，下一轮开跑
/// - `steering`：插话，注入当前轮
/// - `context`：运行时上下文注入（非用户输入，横幅计数不含它）
///
/// `rpcId` 与本地乐观气泡同源（session/prompt 的 requestId），
/// 队列快照到达即代表 Host 已受理 —— 按它把乐观气泡转确认态。
library;

/// 队列条目的放置类型
enum QueuePlacement { queued, steering, context }

/// 一条排队/插话消息（不可变，供 UI 与对账使用）
class QueuedMessage {
  final String id;
  final QueuePlacement placement;

  /// 发送方预先给出的 requestId；与乐观气泡对账的钥匙（可能缺省）
  final String? rpcId;
  final String content;

  const QueuedMessage({
    required this.id,
    required this.placement,
    required this.content,
    this.rpcId,
  });

  /// 横幅计数是否统计它（context 是上下文注入，不是用户的排队消息）
  bool get countsAsUserQueue =>
      placement == QueuePlacement.queued ||
      placement == QueuePlacement.steering;
}

/// 解析 queue 帧的 items；形状异常的条目跳过（fail-soft：横幅不能因
/// 单条脏数据消失，队列权威仍以 Host 快照为准）。
List<QueuedMessage> parseQueuedItems(List<Map<String, dynamic>> items) {
  final out = <QueuedMessage>[];
  for (final raw in items) {
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    var placement = QueuePlacement.queued;
    final p = raw['placement']?.toString();
    if (p == 'steering') {
      placement = QueuePlacement.steering;
    } else if (p == 'context') {
      placement = QueuePlacement.context;
    }
    String? rpcId;
    final source = raw['rpcId'];
    if (source is String && source.isNotEmpty) rpcId = source;
    // message.content 可能是字符串或 content blocks 数组
    final message = raw['message'];
    var content = '';
    if (message is Map) {
      final c = message['content'];
      content = _flattenContent(c);
    } else if (raw['content'] != null) {
      content = _flattenContent(raw['content']);
    }
    out.add(QueuedMessage(
      id: id,
      placement: placement,
      rpcId: rpcId,
      content: content,
    ));
  }
  return out;
}

String _flattenContent(Object? content) {
  if (content is String) return content;
  if (content is List) {
    return content
        .whereType<Map>()
        .map((b) => b['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .join('\n');
  }
  return content?.toString() ?? '';
}
