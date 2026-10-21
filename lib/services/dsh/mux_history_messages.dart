part of 'mux_history.dart';

/// 历史气泡：role/text/id，用户消息额外保留 rpcId 供乐观回显对账
typedef HistoryMessage = ({
  String role,
  String text,
  String id,
  String? rpcId,
});

/// entry: { event: { type, seq, time, data, surfaceOp? }, view? }
///
/// 过滤规则与 DSH Web 的可见 Chat 行对齐：
/// - `user/message` 只保留 `source.kind == "user"` 的真人输入；
///   runtime-context / skill-catalog / time-context / compact-checkpoint
///   等注入上下文不上屏；
/// - `assistant/message` 只保留每个 turn 最后一个 step 的最终回答；
///   中间 step 的文本（通常伴随 tool-call）属于过程内容，不上屏；
/// - 只接受 append surface，replacement 副本是模型可见面，不是人类记录；
/// - reasoning / tool 块不参与文本拼接。
List<HistoryMessage> parseHistory(List<dynamic> entries) {
  final users = <int, HistoryMessage>{};
  final assistants = <int, ({
    String text,
    String id,
    int? turn,
    int? step,
    bool hasTool,
  })>{};
  final seenUserIds = <String>{};

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry is! Map<String, dynamic>) continue;
    final event = entry['event'];
    if (event is! Map<String, dynamic>) continue;
    if (!isAppendSurface(event)) continue;

    final type = event['type'] as String? ?? '';
    final seq = '${event['seq'] ?? ''}';
    final data = event['data'];
    if (data is! Map<String, dynamic>) continue;

    if (type == 'user/message') {
      if (!isHumanUserMessage(data)) continue;
      final source = data['source'];
      final text = extractContentBlocks(data['content'], lastOnly: true);
      if (text.isEmpty) continue;
      final messageId = data['id'] as String?;
      final rpcId = source['rpcId'] as String?;
      final dedupeKey = messageId ?? rpcId;
      if (dedupeKey != null &&
          dedupeKey.isNotEmpty &&
          !seenUserIds.add(dedupeKey)) {
        continue;
      }
      users[i] = (
        role: 'user',
        text: text,
        id: 'u$seq',
        rpcId: rpcId,
      );
    } else if (type == 'assistant/message') {
      final message = data['message'];
      final content = message is Map ? message['content'] : null;
      final text = extractContentBlocks(content);
      if (text.isEmpty) continue;
      assistants[i] = (
        text: text,
        id: 'a$seq',
        turn: (data['turn'] as num?)?.toInt(),
        step: (data['step'] as num?)?.toInt(),
        hasTool: hasToolCallBlock(content),
      );
    }
  }

  // 每个 turn 只取最后一个 step 的最终回答；同一步多条时取最后一条。
  // 没有 turn 的旧数据保持兼容：逐条保留非过程文本。
  final selected = <int>{};
  final byTurn = <int, List<int>>{};
  for (final entry in assistants.entries) {
    final turn = entry.value.turn;
    if (turn == null) {
      if (!entry.value.hasTool) selected.add(entry.key);
    } else {
      byTurn.putIfAbsent(turn, () => []).add(entry.key);
    }
  }
  for (final indexes in byTurn.values) {
    var maxStep = -1;
    for (final i in indexes) {
      final step = assistants[i]!.step ?? 0;
      if (step > maxStep) maxStep = step;
    }
    int? lastOfStep;
    for (final i in indexes) {
      if ((assistants[i]!.step ?? 0) == maxStep) lastOfStep = i;
    }
    if (lastOfStep != null && !assistants[lastOfStep]!.hasTool) {
      selected.add(lastOfStep);
    }
  }

  // 按原始事件顺序输出，保持用户/回复交错关系。
  final out = <HistoryMessage>[];
  for (var i = 0; i < entries.length; i++) {
    final user = users[i];
    if (user != null) out.add(user);
    final assistant = assistants[i];
    if (assistant != null && selected.contains(i)) {
      out.add((
        role: 'assistant',
        text: assistant.text,
        id: assistant.id,
        rpcId: null,
      ));
    }
  }
  return out;
}

/// 只接受 append-origin surface 事件；没有 surfaceOp 的旧数据视为 append。
bool isAppendSurface(Map<String, dynamic> event) {
  final op = event['surfaceOp'];
  return op == null || op == 'append';
}

/// 是否是真人输入的 user/message。
///
/// DSH 把 runtime-context / skill-catalog / time-context / compact-checkpoint
/// 等注入上下文也记成 `user/message`，只有 `source.kind == "user"` 属于
/// 用户可见的聊天记录。
bool isHumanUserMessage(Map<String, dynamic> data) {
  final source = data['source'];
  return source is Map && source['kind'] == 'user';
}
