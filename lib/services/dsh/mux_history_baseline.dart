part of 'mux_history.dart';

/// 重连基线的助手流解码（session/follow snapshot.assistantStream）
///
/// 协议依据 DSH_REMOTE_STREAM_MUX_PROTOCOL.md L1473-1487：基线的
/// `activeAttempt.stream` 是紧凑的 `AssistantStreamRecord` 数组
/// （`packages/llm/llm/src/assistant-stream.ts:20-44`）：
///
/// ```ts
/// export type AssistantStreamRecord =
///   | { type: 'text-chunks'; time0; index; dt: number[]; texts: string[] }
///   | { type: 'reasoning-chunks'; time0; index; dt: number[]; texts: string[] }
///   | { type: 'tool-call-chunks'; time0; index; dt; id; name?; args: string[] }
///   | { type: 'chunk'; time; chunk: StreamChunk }
/// ```
///
/// 之前的实现只在数组里找 `type == 'text-delta'` —— 该类型只存在于
/// **单帧 chunk**（assistant-stream 帧的内层 StreamChunk），基线记录里
/// 根本没有，所以重连时进行中的流式文本全部丢失（§5.1 要求 partial
/// text 存活）。本解码器同时兼容：
/// - 紧凑记录 `text-chunks` / `reasoning-chunks`（texts 数组按序拼接）；
/// - 包裹记录 `{type:'chunk', time, chunk:{type:'text-delta'|'reasoning-delta'}}`
///   （Host 累加器的原始推送形，见 spec §5.1 `attempt.stream.push({time, chunk})`）；
/// - 旧线形 `{time, chunk:{...}}`（无顶层 type），按包裹记录处理。
/// - `tool-call-chunks` 不在此重放：进行中的工具调用由 journal 的
///   tool/call（快照窗口内）与后续 tool/result 收尾，重放会双计。
class AssistantBaselineChunk {
  /// 所在 chunk 的稠密序号（记录的 index；包裹记录缺 index 时取内层）
  final int index;

  /// 是否 reasoning 增量
  final bool isReasoning;

  final String text;

  const AssistantBaselineChunk({
    required this.index,
    required this.isReasoning,
    required this.text,
  });
}

/// 基线 stream 数组 → 按 chunk 稠密序号排序的增量列表
List<AssistantBaselineChunk> decodeAssistantBaselineStream(List<dynamic> stream) {
  final members = <AssistantBaselineChunk>[];
  for (final item in stream) {
    if (item is! Map<String, dynamic>) continue;
    final type = item['type'] as String?;
    if (type == 'text-chunks' || type == 'reasoning-chunks') {
      final text = (item['texts'] as List? ?? []).whereType<String>().join();
      if (text.isNotEmpty) {
        members.add(AssistantBaselineChunk(
          index: (item['index'] as num?)?.toInt() ?? 0,
          isReasoning: type == 'reasoning-chunks',
          text: text,
        ));
      }
      continue;
    }
    // 包裹记录 / 旧线形：取内层 StreamChunk
    final chunk = item['chunk'];
    if (chunk is! Map<String, dynamic>) continue;
    final chunkType = chunk['type'] as String?;
    if (chunkType != 'text-delta' && chunkType != 'reasoning-delta') continue;
    final text = chunk['text'] as String? ?? '';
    if (text.isEmpty) continue;
    members.add(AssistantBaselineChunk(
      index: (item['index'] as num?)?.toInt() ??
          (chunk['index'] as num?)?.toInt() ??
          0,
      isReasoning: chunkType == 'reasoning-delta',
      text: text,
    ));
  }
  // 数组本身有序（Host 累加器顺序 push），按 index 排序是防御乱序线形
  members.sort((a, b) => a.index.compareTo(b.index));
  return members;
}
