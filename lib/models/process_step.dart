/// 过程步骤条目（与后端无关：DSH 与 opencode 产出同一套步骤）
///
/// 一个 turn 内的「过程内容」——Web 端折叠进过程区的那些东西：
/// 工具调用前的过程文本、每次工具调用及其结果状态。
/// 运行中在过程步骤卡里实时展开，turn 收尾后收起成一行摘要。
enum ProcessEntryKind { text, tool }

enum ProcessEntryStatus { running, done, failed }

class ProcessEntry {
  final String id;
  final ProcessEntryKind kind;
  final ProcessEntryStatus status;

  /// text 条目的过程文本；tool 条目为空
  final String text;

  /// tool 条目的工具名与参数摘要；text 条目为空
  final String toolName;
  final String? toolDetail;

  const ProcessEntry.text({
    required this.id,
    required this.text,
  })  : kind = ProcessEntryKind.text,
        status = ProcessEntryStatus.done,
        toolName = '',
        toolDetail = null;

  const ProcessEntry.tool({
    required this.id,
    required this.toolName,
    this.toolDetail,
    this.status = ProcessEntryStatus.running,
  })  : kind = ProcessEntryKind.tool,
        text = '';

  /// 只有 tool 条目有状态迁移（running → done/failed）；
  /// text 条目一旦固化就不再变，copyWith 返回自身。
  ProcessEntry copyWith({ProcessEntryStatus? status}) {
    if (kind != ProcessEntryKind.tool) return this;
    return ProcessEntry.tool(
      id: id,
      toolName: toolName,
      toolDetail: toolDetail,
      status: status ?? this.status,
    );
  }

  bool get isRunning => status == ProcessEntryStatus.running;
}
