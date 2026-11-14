/// 过程步骤条目（与后端无关：DSH 与 opencode 产出同一套步骤）
///
/// 一个 turn 内的「过程内容」——Web 端折叠进过程区的那些东西：
/// 工具调用前的过程文本、reasoning（思考过程）、每次工具调用及其结果状态。
/// 运行中在过程步骤卡里实时展开，turn 收尾后收起成一行摘要。
enum ProcessEntryKind { text, reasoning, tool }

/// Web 端工具行四态（DSH_WEB_CLIENT_PORTING_SPEC.md §9.1）：
/// `running`（无结果）→ `stopped`（error.code == 'interrupted'）→
/// `error`（isError）→ `ok`，优先级即此顺序。
enum ProcessEntryStatus { running, done, failed, stopped }

class ProcessEntry {
  final String id;
  final ProcessEntryKind kind;
  final ProcessEntryStatus status;

  /// text / reasoning 条目的内容；tool 条目为空
  final String text;

  /// tool 条目的工具名与参数摘要；text / reasoning 条目为空
  final String toolName;
  final String? toolDetail;

  const ProcessEntry.text({
    required this.id,
    required this.text,
  })  : kind = ProcessEntryKind.text,
        status = ProcessEntryStatus.done,
        toolName = '',
        toolDetail = null;

  /// reasoning 条目：实时流式累积时 status 为 running（「思考中」），
  /// 历史装载 / 已落定时为 done。
  const ProcessEntry.reasoning({
    required this.id,
    required this.text,
    this.status = ProcessEntryStatus.running,
  })  : kind = ProcessEntryKind.reasoning,
        toolName = '',
        toolDetail = null;

  const ProcessEntry.tool({
    required this.id,
    required this.toolName,
    this.toolDetail,
    this.status = ProcessEntryStatus.running,
  })  : kind = ProcessEntryKind.tool,
        text = '';

  /// tool 条目迁移状态（running → done/failed/stopped）；reasoning 条目
  /// 可更新累积文本与状态；text 条目一旦固化就不再变，copyWith 返回自身。
  ProcessEntry copyWith({ProcessEntryStatus? status, String? text}) {
    switch (kind) {
      case ProcessEntryKind.tool:
        return ProcessEntry.tool(
          id: id,
          toolName: toolName,
          toolDetail: toolDetail,
          status: status ?? this.status,
        );
      case ProcessEntryKind.reasoning:
        return ProcessEntry.reasoning(
          id: id,
          text: text ?? this.text,
          status: status ?? this.status,
        );
      case ProcessEntryKind.text:
        return this;
    }
  }

  bool get isRunning => status == ProcessEntryStatus.running;
}
