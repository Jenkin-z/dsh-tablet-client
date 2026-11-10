/// 轮次状态机（对标 dsh-go Runtime State V4 的最小化状态模型）
///
/// 设计要点（源自 dsh-go V4）：
/// - **状态显式化**：`phase` 单一字段表达轮次阶段，替代过去
///   agentRunning / assistantStreaming / activeTool 三个平铺字段的隐式组合。
/// - **generation CAS**：每次有效迁移 generation 单调 +1；迟到/乱序的
///   旧状态（generation 不大于当前）在 `SessionState.applyTurnState`
///   处直接丢弃，是存储侧最后一道安全闸。
/// - **原子提交**：一个命令产出一个 TurnState，由唯一写入口
///   （TurnSupervisor）一次性应用 —— UI 只见迁移前后，不见中间帧。
library;

/// 轮次阶段
///
/// - idle：空闲
/// - sending：本地乐观发送已发生、权威确认未到（乐观运行态桥接的显式化）
/// - queued：本轮已收尾但 Host 队列还有本会话的排队消息（turn/end 且队列非空）
/// - running：权威的 turn 激活中（turn/start～turn/end 之间）
enum TurnPhase { idle, sending, queued, running }

/// 当前会话的轮次状态快照（不可变）
class TurnState {
  /// 单调递增的迁移序号；0 = 初始态
  final int generation;
  final TurnPhase phase;

  /// running 的修饰位：assistant 流式输出中
  final bool streaming;

  /// running 的修饰位：正在执行的工具摘要（状态栏）
  final String? activeTool;

  /// 本轮是否已收尾（turn/end 已处理）。
  /// 收尾后到达的 running:true / 迟到 chunk 是重放残留，必须被闸门挡住。
  final bool turnClosed;
  final DateTime updatedAt;

  const TurnState({
    required this.generation,
    required this.phase,
    required this.streaming,
    required this.activeTool,
    required this.turnClosed,
    required this.updatedAt,
  });

  factory TurnState.initial() => TurnState(
        generation: 0,
        phase: TurnPhase.idle,
        streaming: false,
        activeTool: null,
        turnClosed: false,
        updatedAt: DateTime.now(),
      );

  /// 对 UI 而言「忙」：发送中 / 排队中 / 运行中都算 ——
  /// 停止按钮在 queued 相位同样保持，杜绝 turn/end→turn/start 间隙闪断。
  bool get busy => phase != TurnPhase.idle;

  /// 观测字段是否与 [other] 相同（不含 generation/updatedAt 这类簿记字段）。
  /// 全部相同 = 本次命令无效迁移，不 bump generation、不广播。
  bool sameAs(TurnState other) =>
      phase == other.phase &&
      streaming == other.streaming &&
      activeTool == other.activeTool &&
      turnClosed == other.turnClosed;

  TurnState copyWith({
    TurnPhase? phase,
    bool? streaming,
    String? activeTool,
    bool clearActiveTool = false,
    bool? turnClosed,
  }) =>
      TurnState(
        generation: generation,
        phase: phase ?? this.phase,
        streaming: streaming ?? this.streaming,
        activeTool: clearActiveTool ? null : (activeTool ?? this.activeTool),
        turnClosed: turnClosed ?? this.turnClosed,
        updatedAt: updatedAt,
      );

  @override
  String toString() =>
      'TurnState(gen=$generation, phase=$phase, streaming=$streaming, '
      'tool=$activeTool, closed=$turnClosed)';
}
