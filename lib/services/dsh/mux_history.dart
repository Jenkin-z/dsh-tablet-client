/// mux / history 解析：纯函数，无 WebSocket 依赖。
library;

import 'dart:convert';

import '../../models/process_step.dart';

part 'mux_history_messages.dart';
part 'mux_history_baseline.dart';

// ── mux → dispatcher 的同微任务 side-channel ─────────────────
//
// MuxStream 的回调字段类型锁定在 mux_stream.dart（本任务禁区），无法为
// reasoning 增量 / 工具中断新增第二参数。这里用库级变量做 side-channel：
// 写与读发生在**同一个事件循环微任务**里（先写后读、读后即清），
// 不存在跨事件串扰。

/// 下一次 onTextDelta 实为 reasoning 增量（assistant-stream 的
/// reasoning-delta chunk / 重连基线的 reasoning-chunks 记录）。
bool muxNextTextDeltaIsReasoning = false;

/// 最近一次 tool/result 是否因「用户停止」中断（error.code ==
/// 'interrupted'）；Web 端 §9.1 的优先级是 stopped > error。
bool muxToolResultWasInterrupted = false;

/// 被停止的 assistant 消息的尾部标记（Web 端 §14.7 的 message.stopped）。
/// 实时定稿（onAssistantFinal）与历史装载（parseHistory）共用同一文案。
const String interruptedSuffix = '（已停止）';

/// 从 turn/end 的 reason 字段提取错误信息（如有）
///
/// `reason.kind == 'error'` 时取 `reason.error.message`；error 不是对象
/// 或没有 message 时按「未知错误」处理。实时分发（mux_session_handler）
/// 与历史装载（parseHistory）共用，保证 turn-error 上屏文本一致。
String? extractTurnEndError(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final reason = data['reason'];
  if (reason is! Map<String, dynamic>) return null;
  if (reason['kind'] != 'error') return null;
  final error = reason['error'];
  if (error is Map<String, dynamic>) {
    return error['message'] as String? ?? '未知错误';
  }
  return '未知错误';
}

/// 工具结果是否因「用户停止」而中断（error.code == 'interrupted'）
///
/// Web 端的行状态优先级是 stopped > error > ok（§9.1：
/// `error?.code === 'interrupted' ? 'stopped' : isError ? 'error' : 'ok'`）。
bool toolResultStopped(dynamic data) {
  if (data is! Map) return false;
  final error = data['error'];
  return error is Map && error['code'] == 'interrupted';
}

/// 从 assistant/message 的 message 字段提取纯文本
String extractAssistantText(dynamic message) {
  if (message is! Map<String, dynamic>) return '';
  return extractContentBlocks(message['content']);
}

/// content 是否包含 tool-call 块
///
/// 带 tool-call 的 assistant 消息是过程步骤（Web 端折叠在过程区），
/// 不是最终回复；历史与实时路径都必须用同一规则判断。
bool hasToolCallBlock(dynamic content) {
  if (content is! List) return false;
  for (final part in content) {
    if (part is Map && part['type'] == 'tool-call') return true;
  }
  return false;
}

/// 从 assistant/message 提取“最终回答”文本
///
/// - reasoning / tool 块不会被 [extractContentBlocks] 拼入；
/// - 只要 content 里出现 tool-call，整条消息都按过程处理，返回空串。
String extractAssistantReply(dynamic message) {
  if (message is! Map<String, dynamic>) return '';
  final content = message['content'];
  if (hasToolCallBlock(content)) return '';
  return extractContentBlocks(content);
}

/// 从 content 块列表提取纯文本：只取 type == 'text' 的块，
/// 多块用空行（'\n\n'）连接。
///
/// 之前的实现有两种丢/黏问题：lastOnly 只留最后一个块（用户消息的
/// 多段输入被丢），非 lastOnly 直接 buf.write 把多块黏成一段
/// （assistant 多段回答没有分隔）。与 Web 端按块渲染的观感对齐。
String extractContentBlocks(dynamic content) {
  if (content is! List) return '';
  final parts = <String>[];
  for (final part in content) {
    if (part is Map<String, dynamic> && part['type'] == 'text') {
      final t = part['text'] as String? ?? '';
      if (t.isNotEmpty) parts.add(t);
    }
  }
  return parts.join('\n\n');
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
