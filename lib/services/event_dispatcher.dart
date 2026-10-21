import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/pending.dart';
import 'app_visibility.dart';
import 'dsh/mux_history.dart';
import 'model_catalog.dart';
import 'notification_service.dart';
import 'session_state.dart';
import 'sound_service.dart';

part 'event_streaming_text.dart';
part 'event_message_reconcile.dart';
part 'event_turn_session.dart';
part 'event_pending_review.dart';

/// 库内共享宿主：声明 dispatcher 各分片（mixin）依赖的字段与方法，
/// 本身不对外暴露。[EventDispatcher] 继承它并混入各职责分片。
abstract class _EventDispatcherCore {
  final SessionState state;

  // 回调钩子声明为抽象 getter（字段由 [EventDispatcher] 定义，
  // initializing formal 指向子类字段）。

  /// 运行状态推送的外部观察者（如 ServerManager 的实时刷新）
  void Function(String sessionId, bool running)? get onSessionStatusExternal;

  void Function(String sessionId, String message)? get onSessionError;
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
  final Map<String, String> _pendingEcho = {};

  /// 本轮是否已经收到 `turn/end`。
  ///
  /// 用来挡住迟到的 assistant chunk：它不该把刚结束的运行态又顶起来。
  bool _turnClosed = false;

  _EventDispatcherCore(this.state);
}

/// 事件统一入口：所有后端事件都先进这里，再更新状态中枢
///
/// 不要在其他模块里自己处理后端事件。
/// 所有事件都必须通过这个 dispatcher 分发 —— DSH（mux）与 opencode（SSE）
/// 走同一套对账/状态迁移逻辑，页面与状态中枢对后端无感。
///
/// 按职责拆分（mixin 分片，同库内共享宿主字段，对外 API 不变）：
/// - event_message_reconcile.dart：消息装载 / 本地乐观气泡对账
/// - event_streaming_text.dart：流式增量缓冲与 assistant 定稿
/// - event_turn_session.dart：session 状态 / tool / turn 生命周期 / 投影
/// - event_pending_review.dart：审批 / 提问 / 表单
class EventDispatcher extends _EventDispatcherCore
    with
        EventDispatcherStreaming,
        EventDispatcherMessages,
        EventDispatcherTurnSession,
        EventDispatcherPendingReview {
  // 回调钩子字段：core 里声明为抽象 getter，这里定义真实字段
  //（initializing formal 指向它们，同时生成 core getter 需要的 setter）。
  @override
  void Function(String sessionId, bool running)? onSessionStatusExternal;
  @override
  void Function(String sessionId, String message)? onSessionError;
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

  EventDispatcher({
    required SessionState state,
    this.onSessionStatusExternal,
    this.onSessionError,
    this.onScrollToBottom,
    this.onJumpToLatest,
    this.onShowQuestionDialog,
    this.onPopQuestionDialog,
    this.onShowFormDialog,
    this.onPopFormDialog,
    this.onShowSnackBar,
  }) : super(state);

  // ── 重置 ────────────────────────────────────────

  void reset() {
    _clearDelta();
    _turnClosed = false;
    _messages.clear();
    _seenUserSeq.clear();
    _seenUserIds.clear();
    _pendingEcho.clear();
    _currentAssistantId = null;
    _bumpMessages();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _deltaFlushTimer?.cancel();
    messagesRevision.dispose();
  }
}
