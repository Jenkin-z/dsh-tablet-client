import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/pending.dart';
import '../models/process_step.dart';
import '../models/queued_message.dart';
import 'dsh/mux_history.dart';
import 'model_catalog.dart';
import 'notification_service.dart';
import 'session_idle.dart';
import 'session_state.dart';
import 'sound_service.dart';
import 'turn_supervisor.dart';

part 'event_streaming_text.dart';
part 'event_message_reconcile.dart';
part 'event_turn_session.dart';
part 'event_pending_review.dart';
part 'event_process_steps.dart';
part 'event_queue.dart';

/// 库内共享宿主：声明 dispatcher 各分片（mixin）依赖的字段与方法，
/// 本身不对外暴露。[EventDispatcher] 继承它并混入各职责分片。
abstract class _EventDispatcherCore {
  final SessionState state;

  // 回调钩子声明为抽象 getter（字段由 [EventDispatcher] 定义，
  // initializing formal 指向子类字段）。

  /// 运行状态推送的外部观察者（如 ServerManager 的实时刷新）
  void Function(String sessionId, bool running)? get onSessionStatusExternal;

  /// 通知 payload 用的 serverId 提供者（点击通知跳转会话）。
  /// dispatcher 只服务当前 active 的那台机器（ChatScreen 按
  /// activeServerId 重建），通知时刻的 activeServerId 就是归属机器。
  String? Function()? get serverIdProvider;

  VoidCallback? get onScrollToBottom;
  VoidCallback? get onJumpToLatest;
  VoidCallback? get onShowQuestionDialog;
  VoidCallback? get onPopQuestionDialog;
  VoidCallback? get onShowFormDialog;
  VoidCallback? get onPopFormDialog;
  void Function(String message)? get onShowSnackBar;

  // ── 流式增量 ────────────────────────────────────

  final StringBuffer _deltaBuffer = StringBuffer();
  Timer? _deltaFlushTimer;
  final List<ChatMessage> _messages = [];
  final Set<String> _seenUserSeq = {};
  final Set<String> _seenUserIds = {};

  /// 当前 turn 正在展示的 assistant 气泡 id。
  ///
  /// 一个 turn 内可能有多个 step（过程文本 + 最终回答），Web 端只把最终
  /// 回答留在消息流里；这里用同一个 id 就地替换，避免每个 step 新增气泡。
  String? _currentAssistantId;

  /// 丢弃当前 assistant 气泡（过程步骤 / 重试 / 工具调用前的文本）。
  void _dropCurrentAssistant() {
    final id = _currentAssistantId;
    if (id == null) return;
    _currentAssistantId = null;
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == id);
    if (_messages.length != before) _bumpMessages();
  }

  // ── 过程步骤（实现见 event_process_steps.dart）────
  //
  // 声明在 core：TurnSession / Messages 两个分片要调用它们，
  // 而跨 mixin 静态可见性只到共同超接口为止。

  /// 固化过程文本：优先用定稿文本（DSH 的 assistant/message 带 tool-call
  /// 时整段到达），否则取当前流式气泡 + 未 flush 的增量
  void captureProcessText(String finalized);

  /// 工具调用到来：固化过程文本 + 追加 running 工具条目
  void addProcessStep(String toolName, String? arguments);

  /// 工具结果到达：收尾最后一个 running 条目
  void completeProcessTool(bool failed);

  /// turn 收尾：过程步骤卡收起
  void collapseProcess();

  /// 新一轮开始：清空上一轮过程条目
  void resetProcess();

  /// 历史装载 / 重置时静默清理
  void clearProcessSilently();

  /// 丢弃尚未 flush 的增量：工具调用/换轮后，缓冲里的过程文本不能再上屏。
  void _clearDelta() {
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _deltaBuffer.clear();
  }

  /// 消息列表版本号。
  ///
  /// 流式输出只改消息内容，不改运行态/审批等全局状态。让消息区单独监听
  /// 这个版本号，避免每来一个 chunk 就 `state.notify()` 把整棵树重绘一遍。
  final ValueNotifier<int> messagesRevision = ValueNotifier<int>(0);
  bool _disposed = false;

  void _bumpMessages() {
    // 后端关闭时可能还有排队的事件回调；不要再去碰已释放的 notifier。
    if (!_disposed) messagesRevision.value++;
  }

  /// 本地乐观气泡的 rpcId → 内容。
  ///
  /// Web 端的对账是双层的（ChatView.tsx:139-157）：durable 消息一出现就按
  /// rpcId 把本地回显滤掉；这里的做法等价 —— 收到带同一 rpcId 的 durable
  /// user/message 时撤掉本地那条。
  ///
  /// 生命周期：发出即入表；POST 成功确认后**不移除**（转入 [_ackedEcho]
  /// 标记已确认）—— opencode 的 durable 消息不带 rpcId，后续要靠这张表
  /// 按**内容**对账最老一条本地回显（见 event_message_reconcile 的
  /// 内容兜底路径）。只有真正对账掉 / 发送失败才出表。
  final Map<String, String> _pendingEcho = {};

  /// 已被服务端确认（POST 2xx）但还没被 durable 消息对账掉的回显。
  /// 影响两件事：历史装载补回时不再显示 pending 态；内容兜底对账的候选。
  final Set<String> _ackedEcho = {};

  /// 轮次状态的唯一写入口（Runtime Supervisor）。
  /// 所有运行态迁移都经它；`_turnClosed` 闸门语义收敛在其内部策略。
  TurnSupervisor get supervisor;

  /// 本轮是否已收尾（turn/end 已处理）。
  /// 真源在 supervisor；保留这个 getter 让各分片（含过程步骤卡）
  /// 的既有判断零改动。
  bool get _turnClosed => supervisor.turnClosed;

  /// 乐观气泡转确认态（实现见 event_message_reconcile.dart；
  /// 声明在 core 供 Queue 分片跨 mixin 调用）
  void confirmLocalUserMessage(String rpcId);

  _EventDispatcherCore(this.state);
}

/// 事件统一入口：所有后端事件都先进这里，再更新状态中枢
///
/// 不要在其他模块里自己处理后端事件。
/// 所有事件都必须通过这个 dispatcher 分发 —— DSH（mux）与 opencode（SSE）
/// 走同一套对账/状态迁移逻辑，页面与状态中枢对后端无感。
/// 轮次运行态（running/streaming/activeTool）的写入统一经 [TurnSupervisor]。
///
/// 按职责拆分（mixin 分片，同库内共享宿主字段，对外 API 不变）：
/// - event_message_reconcile.dart：消息装载 / 本地乐观气泡对账
/// - event_streaming_text.dart：流式增量缓冲与 assistant 定稿
/// - event_turn_session.dart：session 状态 / tool / turn 生命周期 / 投影
/// - event_pending_review.dart：审批 / 提问 / 表单
/// - event_process_steps.dart：过程步骤卡（turn 内过程内容）
/// - event_queue.dart：Host 队列（排队/插话）快照与对账
class EventDispatcher extends _EventDispatcherCore
    with
        EventDispatcherStreaming,
        EventDispatcherMessages,
        EventDispatcherTurnSession,
        EventDispatcherPendingReview,
        EventDispatcherProcess,
        EventDispatcherQueue {
  // 回调钩子字段：core 里声明为抽象 getter，这里定义真实字段
  //（initializing formal 指向子类字段，同时生成 core getter 需要的 setter）。
  @override
  void Function(String sessionId, bool running)? onSessionStatusExternal;
  @override
  String? Function()? serverIdProvider;
  @override
  VoidCallback? onScrollToBottom;
  @override
  VoidCallback? onJumpToLatest;
  @override
  VoidCallback? onShowQuestionDialog;
  @override
  VoidCallback? onPopQuestionDialog;
  @override
  VoidCallback? onShowFormDialog;
  @override
  VoidCallback? onPopFormDialog;
  @override
  void Function(String message)? onShowSnackBar;

  @override
  final TurnSupervisor supervisor;

  EventDispatcher({
    required SessionState state,
    TurnSupervisor? supervisor,
    this.onSessionStatusExternal,
    this.serverIdProvider,
    this.onScrollToBottom,
    this.onJumpToLatest,
    this.onShowQuestionDialog,
    this.onPopQuestionDialog,
    this.onShowFormDialog,
    this.onPopFormDialog,
    this.onShowSnackBar,
  })  : supervisor = supervisor ??
            // 独立构造（多为测试）：队列判定直接读状态中枢的队列视图
            TurnSupervisor(
              state,
              hasQueuedWork: () => state.queuedCountOf(state.sessionId) > 0,
            ),
        super(state);

  // ── 重置 ────────────────────────────────────────

  void reset() {
    _clearDelta();
    // 轮次状态一并归零（turnClosed 回到未收尾、phase 回到 idle）
    supervisor.reset();
    _messages.clear();
    _seenUserSeq.clear();
    _seenUserIds.clear();
    _pendingEcho.clear();
    _ackedEcho.clear();
    _currentAssistantId = null;
    clearProcessSilently();
    _bumpMessages();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _deltaFlushTimer?.cancel();
    messagesRevision.dispose();
  }
}
