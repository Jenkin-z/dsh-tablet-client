/// mux / history 解析：纯函数，无 WebSocket 依赖。
library;

/// 从 assistant/message 的 message 字段提取纯文本
String extractAssistantText(dynamic message) {
  if (message is! Map<String, dynamic>) return '';
  return extractContentBlocks(message['content']);
}

String extractContentBlocks(dynamic content) {
  if (content is! List) return '';
  final buf = StringBuffer();
  for (final part in content) {
    if (part is Map<String, dynamic> && part['type'] == 'text') {
      buf.write(part['text'] as String? ?? '');
    }
  }
  return buf.toString();
}

typedef ToolViewRecord = ({
  String? callId,
  String card,
  String title,
  List<Map<String, String?>> diffs,
  bool done,
  int? turn,
});

ToolViewRecord? parseDiffView({
  required dynamic viewSlot,
  required String eventType,
  required dynamic data,
  required bool done,
}) {
  if (viewSlot is! Map<String, dynamic>) return null;
  final v = viewSlot['view'];
  if (v is! Map<String, dynamic> || v['card'] != 'diff') return null;
  final rawDiffs = v['diffs'];
  if (rawDiffs is! List) return null;
  final diffs = <Map<String, String?>>[];
  for (final d in rawDiffs) {
    if (d is! Map<String, dynamic>) continue;
    diffs.add({
      'path': d['path'] as String? ?? '',
      'oldText': d['oldText'] as String?,
      'newText': d['newText'] as String? ?? '',
    });
  }
  if (diffs.isEmpty) return null;
  String? callId;
  int? turn;
  if (data is Map<String, dynamic>) {
    callId = data['callId'] as String?;
    turn = data['turn'] as int?;
  }
  return (
    callId: callId,
    card: 'diff',
    title: v['title'] as String? ?? eventType,
    diffs: diffs,
    done: done,
    turn: turn,
  );
}

/// 从 history 条目（含 view 回填）提取 diff 视图记录
List<ToolViewRecord> parseHistoryViews(List<dynamic> entries) {
  final out = <ToolViewRecord>[];
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final event = entry['event'];
    if (event is! Map<String, dynamic>) continue;
    final rec = parseDiffView(
      viewSlot: entry['view'],
      eventType: event['type'] as String? ?? '',
      data: event['data'],
      done: true,
    );
    if (rec != null) out.add(rec);
  }
  return out;
}

/// entry: { event: { type, seq, time, data }, view? }
List<({String role, String text, String id})> parseHistory(
    List<dynamic> entries) {
  final out = <({String role, String text, String id})>[];
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final event = entry['event'];
    if (event is! Map<String, dynamic>) continue;
    final type = event['type'] as String? ?? '';
    final seq = '${event['seq'] ?? ''}';
    final data = event['data'];
    if (data is! Map<String, dynamic>) continue;

    if (type == 'user/message') {
      final text = extractContentBlocks(data['content']);
      if (text.isNotEmpty) out.add((role: 'user', text: text, id: 'u$seq'));
    } else if (type == 'assistant/message') {
      final text = extractAssistantText(data['message']);
      if (text.isNotEmpty) {
        out.add((role: 'assistant', text: text, id: 'a$seq'));
      }
    }
  }
  return out;
}
