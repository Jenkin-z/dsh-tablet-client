import '../models/turn_state.dart';
import 'session_state.dart';

/// 轮次状态的唯一写入口（对标 dsh-go Runtime Supervisor）
///
/// 职责（源自 dsh-go V4 架构）：
/// - **序列化所有运行态迁移**：EventDispatcher 与发送链路都是它的客户端，
///   任何模块不得直接写 SessionState 的轮次字段；
/// - **策略引擎**：`turnClosed` 迟到事件闸门在这里只实现一次
///   （旧实现散落 3 个文件，语义靠注释维持）；
/// - **事务应用**：一个命令产出一个 [TurnState]，经
///   `SessionState.applyTurnState` 一次性广播 —— UI 只见迁移前后，
///   不见中间帧（旧实现 turn/end 连调 6 个 setter、6 次广播）；
/// - **审计**：append-only 环形日志（最近 [_auditLimit] 条），迁移与
///   被闸门拒绝的事件都留痕，可测试可排查。
///
/// 行为等价红线（迁移自 event_turn_session / event_streaming_text /
/// chat_messaging 的既有语义，勿改）：
/// - `running:true` 只在本轮未收尾（`!turnClosed`）时接受；
/// - `running:false` 永远接受（权威自愈通道）；
/// - 乐观发送置位无条件（权威侧随时可纠正，方向安全）；
/// - stale-busy 自愈「只清不设」：证据判定在调用方，本类只落 idle。
class TurnSupervisor {
  final SessionState _state;

  /// 当前会话是否还有排队/插话消息（turn/end 时决定落 queued 还是 idle）
  final bool Function() hasQueuedWork;

  static const int _auditLimit = 50;
  final List<String> _audit = [];

  TurnState _turn = TurnState.initial();

  TurnSupervisor(this._state, {required this.hasQueuedWork});

  // ── 读取 ────────────────────────────────────────

  TurnState get turn => _turn;
  bool get turnClosed => _turn.turnClosed;

  /// 审计日志（最新在后，只读副本）
  List<String> get auditLog => List.unmodifiable(_audit);

  // ── 发送链路（chat_messaging） ───────────────────

  /// 本地乐观发送：点发送 → 权威确认之间的空窗，busy 必须立即可见。
  /// 无条件置 sending（权威 running 状态优先：已在跑就不降级）。
  void beginLocalSend() {
    _commit('beginLocalSend', (c) {
      if (c.phase == TurnPhase.running) return c;
      return c.copyWith(phase: TurnPhase.sending);
    });
  }

  /// 发送失败回滚。仅回滚乐观态；若权威已宣告 running，以权威为准
  /// （旧实现会无条件压平权威状态，属于顺带修复的边界）。
  void failLocalSend() {
    _commit('failLocalSend', (c) {
      if (c.phase != TurnPhase.sending) return c;
      return c.copyWith(phase: TurnPhase.idle);
    });
  }

  // ── turn 生命周期（event_turn_session） ──────────

  /// journal 的 turn/start：权威的「开始工作」，重新武装闸门
  void turnStart() {
    _commit('turnStart', (c) => c.copyWith(
          turnClosed: false,
          phase: TurnPhase.running,
        ));
  }

  /// journal 的 turn/end：收尾。队列非空落 queued（排队消息会让下一轮
  /// 紧接着开始，busy 不得闪断），否则落 idle。
  void turnEnd() {
    _commit('turnEnd', (c) => c.copyWith(
          turnClosed: true,
          streaming: false,
          clearActiveTool: true,
          phase: hasQueuedWork() ? TurnPhase.queued : TurnPhase.idle,
        ));
  }

  /// 队列快照到达且本轮已收尾：排队消息在场 = busy 延续
  void queuePending() {
    _commit('queuePending', (c) {
      if (!c.turnClosed || !hasQueuedWork()) return c;
      return c.copyWith(phase: TurnPhase.queued);
    });
  }

  /// 当前会话队列被清空（Host 已消化或撤走）而 turn/start 未到：
  /// queued 是「队列非空」的投影，空了就不能再占 busy
  void queueDrained() {
    _commit('queueDrained', (c) {
      if (c.phase != TurnPhase.queued) return c;
      return c.copyWith(phase: TurnPhase.idle);
    });
  }

  /// `api-session/status`（权威状态推送，重连时会重放）
  void authorityRunning(bool running) {
    _commit('authorityRunning(${running})', (c) {
      if (running) {
        // 闸门：本轮已收尾后再来的 running:true 是重放残留
        if (c.turnClosed) return c;
        return c.copyWith(phase: TurnPhase.running);
      }
      // running:false 永远接受：失败路径事件全丢时靠它自愈
      return c.copyWith(
        phase: TurnPhase.idle,
        streaming: false,
        clearActiveTool: true,
      );
    }, note: running && _turn.turnClosed ? '拒绝(turnClosed)' : null);
  }

  /// journal 的 tool/call：running 工具条目上状态栏。
  /// 与旧实现一致：无条件置 running（turn 范围内的 follow 事件可信）。
  void toolCall(String? summary) {
    _commit('toolCall', (c) => c.copyWith(
          streaming: false,
          activeTool: summary,
          phase: TurnPhase.running,
        ));
  }

  /// journal 的 tool/result：收工具条目
  void toolResult() {
    _commit('toolResult', (c) => c.copyWith(clearActiveTool: true));
  }

  // ── 流式文本（event_streaming_text） ─────────────

  /// 新一代 assistant 尝试开始（重连基线 / assistant-stream start）：
  /// 重新武装闸门 + 回到 running
  void assistantStreamStart() {
    _commit('assistantStreamStart', (c) => c.copyWith(
          turnClosed: false,
          streaming: false,
          phase: TurnPhase.running,
        ));
  }

  /// 流式 flush（120ms 合帧后）：打字机态 + 未收尾则保持运行
  void streamTick() {
    _commit('streamTick', (c) {
      var next = c.copyWith(streaming: true);
      if (!c.turnClosed && c.phase != TurnPhase.running) {
        next = next.copyWith(phase: TurnPhase.running);
      }
      return next;
    });
  }

  /// assistant 定稿收尾：结束打字机态；[clearTool] 同步收工具条目
  /// （assistant/message 无 tool-call 时）
  void assistantSettled({bool clearTool = false}) {
    _commit('assistantSettled', (c) => c.copyWith(
          streaming: false,
          clearActiveTool: clearTool,
        ));
  }

  // ── 消息域联动（event_message_reconcile） ────────

  /// durable 用户消息到达（含本地回显对账）= 新一轮心智上的开始：
  /// 重新武装闸门；乐观发送态顺势转 running（Host 已落库受理）
  void userMessageArrived() {
    _commit('userMessageArrived', (c) {
      var next = c.copyWith(turnClosed: false);
      if (next.phase == TurnPhase.sending) {
        next = next.copyWith(phase: TurnPhase.running);
      }
      return next;
    });
  }

  /// stale-busy 自愈（「只清不设」）：消息流证据表明空闲，
  /// 调用方判定后调这里落 idle。判定不了就别调用。
  void settleToIdle() {
    _commit('settleToIdle', (c) {
      if (c.phase == TurnPhase.idle) return c;
      return c.copyWith(phase: TurnPhase.idle);
    });
  }

  /// 后端重置 / 会话切换：回到初始态
  void reset() {
    _commit('reset', (c) => TurnState.initial());
  }

  // ── 事务提交 + 审计 ──────────────────────────────

  void _commit(String command, TurnState Function(TurnState c) build,
      {String? note}) {
    final next = build(_turn);
    if (_turn.sameAs(next)) {
      if (note != null) _log('$command $note');
      return;
    }
    final applied = TurnState(
      generation: _turn.generation + 1,
      phase: next.phase,
      streaming: next.streaming,
      activeTool: next.activeTool,
      turnClosed: next.turnClosed,
      updatedAt: DateTime.now(),
    );
    final from = _turn.phase.name;
    _turn = applied;
    _state.applyTurnState(applied);
    _log('$command $from→${applied.phase.name} gen=${applied.generation}'
        '${note == null ? '' : ' $note'}');
  }

  void _log(String line) {
    _audit.add(line);
    if (_audit.length > _auditLimit) _audit.removeRange(0, _audit.length - _auditLimit);
  }
}
