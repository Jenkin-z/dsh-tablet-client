/// mux / history 解析：纯函数，无 WebSocket 依赖。
library;

import 'dart:convert';

/// 从 assistant/message 的 message 字段提取纯文本
String extractAssistantText(dynamic message) {
  if (message is! Map<String, dynamic>) return '';
  return extractContentBlocks(message['content']);
}

String extractContentBlocks(dynamic content, {bool lastOnly = false}) {
  if (content is! List) return '';
  final buf = StringBuffer();
  String? lastText;
  for (final part in content) {
    if (part is Map<String, dynamic> && part['type'] == 'text') {
      final t = part['text'] as String? ?? '';
      if (t.isNotEmpty) {
        lastText = t;
        if (!lastOnly) buf.write(t);
      }
    }
  }
  return lastOnly ? (lastText ?? '') : buf.toString();
}

typedef ToolViewRecord = ({
  String? callId,
  String card,
  String title,
  List<Map<String, String?>> diffs,
  bool done,
  int? turn,
});

/// diff 的唯一权威来源是 `tool/result.data.meta.diffs`
///
/// Host 侧类型：`FsDiffMeta = { diffs: FileDiff[] }`，
/// `FileDiff = { path: string, oldText: string|null, newText: string }`
/// （fs/tool-fs/src/diff.ts）。`oldText == null` 表示整文件新建。
///
/// ⚠️ 线上**不存在** `view` 字段，也没有 `tool/view` 事件 ——
/// 之前按 `entry['view']['view']` 解析，所以变更面板永远是空的。
///
/// 工具调用**参数**里的 diff 属于「意图」，来自 `tool/call.data.arguments`
/// （未解析的 JSON 字符串），需要调用方自行 decode；此处只处理结果侧。
ToolViewRecord? parseDiffView({
  required String eventType,
  required dynamic data,
}) {
  if (eventType != 'tool/result') return null;
  if (data is! Map<String, dynamic>) return null;

  final meta = data['meta'];
  if (meta is! Map) return null;
  final rawDiffs = meta['diffs'];
  if (rawDiffs is! List) return null;

  final diffs = <Map<String, String?>>[];
  for (final d in rawDiffs) {
    if (d is! Map) continue;
    final path = d['path'];
    if (path is! String || path.isEmpty) continue;
    diffs.add({
      'path': path,
      'oldText': d['oldText'] as String?,
      'newText': d['newText'] as String? ?? '',
    });
  }
  if (diffs.isEmpty) return null;

  // callId / 工具名在 message.source 上；标题优先用路径文件名
  final message = data['message'];
  final source = message is Map ? message['source'] : null;
  final callId = source is Map ? source['callId'] as String? : null;
  final toolName = source is Map ? source['name'] as String? : null;
  final title = diffs.length == 1
      ? _basenameOf(diffs.first['path'] ?? '')
      : '${diffs.length} 个文件';

  return (
    callId: callId,
    card: 'diff',
    title: title.isEmpty ? (toolName ?? 'diff') : title,
    diffs: diffs,
    done: true,
    turn: data['turn'] as int?,
  );
}

/// 工具调用是否失败
bool toolResultFailed(dynamic data) {
  if (data is! Map) return false;
  if (data['error'] != null) return true;
  final message = data['message'];
  if (message is! Map) return false;
  final content = message['content'];
  if (content is! List) return false;
  for (final part in content) {
    if (part is Map && part['type'] == 'tool-result') {
      return part['isError'] == true;
    }
  }
  return false;
}

/// 从工具参数里抽一行人类可读摘要
///
/// `tool/call.data.arguments` 是**未解析的 JSON 字符串**，
/// 常见字段优先级：command（命令）> file_path/path（路径）> query > 其余首键。
String? extractToolDetail(String? rawArguments) {
  if (rawArguments == null || rawArguments.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(rawArguments);
  } catch (_) {
    // 不是合法 JSON 就直接截断原文
    return rawArguments.length > 80
        ? '${rawArguments.substring(0, 80)}…'
        : rawArguments;
  }
  if (decoded is! Map) return null;

  for (final key in const ['command', 'file_path', 'path', 'query', 'pattern']) {
    final v = decoded[key];
    if (v is String && v.isNotEmpty) return _shorten(v);
  }
  // 兜底：取第一个字符串值
  for (final v in decoded.values) {
    if (v is String && v.isNotEmpty) return _shorten(v);
  }
  return null;
}

String _shorten(String s) {
  final oneLine = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length > 80 ? '${oneLine.substring(0, 80)}…' : oneLine;
}

String _basenameOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i >= 0 ? path.substring(i + 1) : path;
}

/// 从 history 条目提取 diff 记录
///
/// `records` 的元素与线上 `event` 帧结构完全一致，
/// 因此解析必须与实时路径共用同一套规则。
List<ToolViewRecord> parseHistoryViews(List<dynamic> entries) {
  final out = <ToolViewRecord>[];
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final event = entry['event'];
    if (event is! Map<String, dynamic>) continue;
    final rec = parseDiffView(
      eventType: event['type'] as String? ?? '',
      data: event['data'],
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
      final text = extractContentBlocks(data['content'], lastOnly: true);
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
