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
/// - reasoning / tool 块不参与文本拼接；
/// - `turn/end`（reason.kind == 'error'）落成 system 气泡：Web 端的
///   turn-error 是 durable 节点，重连后仍在（§14.1），历史装载不能丢；
/// - `assistant/message.data.interrupted == true` 在文本尾部追加
///   「已停止」标记，与实时定稿路径共用 [interruptedSuffix]。
List<HistoryMessage> parseHistory(List<dynamic> entries) {
  final users = <int, HistoryMessage>{};
  final assistants = <int, ({
    String text,
    String id,
    int? turn,
    int? step,
    bool hasTool,
  })>{};

  /// turn/end 错误：index → (seq, message)，输出时按事件序落位
  final turnErrors = <int, ({String seq, String message})>{};
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
      // 用户消息取**全部** text 块（多块用空行连接）：
      // 之前 lastOnly 只留最后一块，多段输入会凭空丢字。
      final text = extractContentBlocks(data['content']);
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
      var text = extractContentBlocks(content);
      if (text.isEmpty) continue;
      if (data['interrupted'] == true) {
        // 与实时定稿路径同一文案；空文本不产气泡，无需标记
        text = '$text$interruptedSuffix';
      }
      assistants[i] = (
        text: text,
        id: 'a$seq',
        turn: (data['turn'] as num?)?.toInt(),
        step: (data['step'] as num?)?.toInt(),
        hasTool: hasToolCallBlock(content),
      );
    } else if (type == 'turn/end') {
      // 回合失败落成 system 消息（与实时路径 onSessionError 同格式）
      final error = extractTurnEndError(data);
      if (error != null && error.isNotEmpty) {
        turnErrors[i] = (seq: seq, message: error);
      }
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

  // 按原始事件顺序输出，保持用户/回复/报错的交错关系。
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
    final error = turnErrors[i];
    if (error != null) {
      out.add((
        role: 'system',
        text: error.message,
        id: 'e${error.seq}',
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

/// 从历史事件合成**最后一个 turn** 的过程条目（工具卡恢复）
///
/// Web 端的过程区是 durable 的（journal 里 tool/call + tool/result 都在），
/// 此前历史重载后整卡消失。这里按事件序合成：
/// - `tool/call` → running 的 tool 条目（摘要与实时同一判定 extractToolDetail）；
/// - `tool/result` → 收尾最后一个 running 条目（stopped 优先于 failed，
///   与实时路径同一判定）。
/// 只取最后一个 turn：过程步骤卡只服务当前轮，旧轮次随新一轮退场；
/// turn 字段缺失的旧数据全部保留。
List<ProcessEntry> parseHistoryProcess(List<dynamic> entries) {
  final all = <ProcessEntry>[];
  final turns = <int?>[];
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final event = entry['event'];
    if (event is! Map<String, dynamic>) continue;
    final type = event['type'] as String? ?? '';
    final data = event['data'];
    if (data is! Map<String, dynamic>) continue;
    switch (type) {
      case 'tool/call':
        all.add(ProcessEntry.tool(
          id: 'h${event['seq'] ?? all.length}',
          toolName: data['name'] as String? ?? 'tool',
          toolDetail: extractToolDetail(data['arguments'] as String?),
        ));
        turns.add((data['turn'] as num?)?.toInt());
        break;
      case 'tool/result':
        for (var i = all.length - 1; i >= 0; i--) {
          if (all[i].kind == ProcessEntryKind.tool && all[i].isRunning) {
            all[i] = all[i].copyWith(
              status: toolResultStopped(data)
                  ? ProcessEntryStatus.stopped
                  : (toolResultFailed(data)
                      ? ProcessEntryStatus.failed
                      : ProcessEntryStatus.done),
            );
            break;
          }
        }
        break;
    }
  }
  if (all.isEmpty) return const [];
  // 只保留最后一个 turn 的条目（无 turn 字段时全部保留）
  final lastTurn = turns.whereType<int>().fold<int?>(null, (a, b) => b);
  if (lastTurn == null) return all;
  final out = <ProcessEntry>[];
  for (var i = 0; i < all.length; i++) {
    if (turns[i] == lastTurn) out.add(all[i]);
  }
  return out;
}
