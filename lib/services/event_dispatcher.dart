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

/// 事件统一入口：所有后端事件都先进这里，再更新状态中枢
///
/// 不要在其他模块里自己处理后端事件。
/// 所有事件都必须通过这个 dispatcher 分发 —— DSH（mux）与 opencode（SSE）
/// 走同一套对账/状态迁移逻辑，页面与状态中枢对后端无感。
class EventDispatcher {
  final SessionState state;

  /// 运行状态推送的外部观察者（如 ServerManager 的实时刷新）
  void Function(String sessionId, bool running)? onSessionStatusExternal;

  void Function(String sessionId, String message)? onSessionError;
  VoidCallback? onScrollToBottom;
  VoidCallback? onJumpToLatest;
  VoidCallback? onShowQuestionDialog;
  VoidCallback? onPopQuestionDialog;
  VoidCallback? onShowFormDialog;
  VoidCallback? onPopFormDialog;
  void Function(String message)? onShowSnackBar;

  EventDispatcher({
    required this.state,
    this.onSessionStatusExternal,
    this.onSessionError,
    this.onScrollToBottom,
    this.onJumpToLatest,
    this.onShowQuestionDialog,
    this.onPopQuestionDialog,
    this.onShowFormDialog,
    this.onPopFormDialog,
    this.onShowSnackBar,
  });

  // ── 流式增量 ────────────────────────────────────

  final StringBuffer _deltaBuffer = StringBuffer();
  Timer? _deltaFlushTimer;
  final List<ChatMessage> _messages = [];
  final Set<String> _seenUserSeq = {};

  /// 本地乐观气泡的 rpcId → 内容。
  ///
  /// Web 端的对账是双层的（ChatView.tsx:139-157）：durable 消息一出现就按
  /// rpcId 把本地回显滤掉；这里的做法等价 —— 收到带同一 rpcId 的 durable
  /// user/message 时撤掉本地那条。
  /// 本轮是否已经收到 `turn/end`。
  ///
  /// 用来挡住迟到的 assistant chunk：它不该把刚结束的运行态又顶起来。
  bool _turnClosed = false;

  final Map<String, String> _pendingEcho = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// 本地立刻上屏一条用户气泡（发送后不等后端回显）
  void addLocalUserMessage(String text, String rpcId) {
    _pendingEcho[rpcId] = text;
    _messages.add(ChatMessage(
      id: rpcId,
      role: 'user',
      content: text,
      pending: true,
    ));
    state.notify();
    onScrollToBottom?.call();
  }

  /// 发送失败：把乐观气泡撤掉
  void failLocalUserMessage(String rpcId) {
    if (_pendingEcho.remove(rpcId) == null) return;
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == rpcId && m.pending);
    if (_messages.length != before) state.notify();
  }

  /// 发送成功确认：把乐观气泡就地转为确认态。
  ///
  /// opencode 的 durable 消息不带 rpcId，无法按 id 对账；
  /// POST /prompt 返回 2xx 即服务端已收，此时就地确认即可
  /// （DSH 仍走 [_reconcileEcho] 的 durable 对账，两条路并存）。
  void confirmLocalUserMessage(String rpcId) {
    if (!_pendingEcho.containsKey(rpcId)) return;
    _pendingEcho.remove(rpcId);
    final idx = _messages.indexWhere((m) => m.id == rpcId && m.pending);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(pending: false);
      state.notify();
    }
  }

  /// 用 durable 消息替换乐观气泡（同一 rpcId 只保留一条，最终态为准）
  void _reconcileEcho(String? rpcId, String text) {
    if (rpcId == null || rpcId.isEmpty) return;
    if (_pendingEcho.remove(rpcId) == null) return;
    final idx = _messages.indexWhere((m) => m.id == rpcId && m.pending);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(content: text, pending: false);
    }
  }

  void _touchActivity() {
    state.setLastTurnEnd(null);
  }

  /// 历史装载的公共段：DSH 的 onSnapshot 与 opencode 的 onHistoryLoaded
  /// 共用（重连瞬间自己刚发的消息不能凭空消失，两条路都必须补回未确认回显）。
  void _loadMessages(List<ChatMessage> loaded) {
    _messages.clear();
    _seenUserSeq.clear();
    _messages.addAll(loaded);
    // 快照里没出现、但仍未确认的本地回显要补回去，
    // 否则重连瞬间自己刚发的消息会凭空消失
    for (final entry in _pendingEcho.entries) {
      _messages.add(ChatMessage(
        id: entry.key,
        role: 'user',
        content: entry.value,
        pending: true,
      ));
    }
    state.clearChanges();
    state.notify();
    onJumpToLatest?.call();
  }

  void onSnapshot(List<Map<String, dynamic>> records) {
    final parsed = parseHistory(records);
    _loadMessages(
        parsed.map((p) => ChatMessage(id: p.id, role: p.role, content: p.text)).toList());
    for (final v in parseHistoryViews(records)) {
      state.applyToolView(
        diffs: v.diffs,
        title: v.title,
        done: v.done,
        turn: v.turn,
      );
    }
  }

  /// 历史装载统一入口（opencode 走这条；消息已由 opencode_mapper 转成
  /// [ChatMessage]，装载/对账逻辑与 DSH 的 onSnapshot 完全同一段）。
  void onHistoryLoaded(List<ChatMessage> messages) => _loadMessages(messages);

  void onTextDelta(String delta) {
    _touchActivity();
    _deltaBuffer.write(delta);
    _deltaFlushTimer ??= Timer(const Duration(milliseconds: 120), _flushDelta);
  }

  void _flushDelta() {
    _deltaFlushTimer = null;
    final text = _deltaBuffer.toString();
    _deltaBuffer.clear();
    if (text.isEmpty) return;

    state.setAssistantStreaming(true);
    // 只有「本轮还没结束」时才把运行态拉起来。
    // 否则一个迟到的 chunk（重连补发、乱序）会把 turn/end 刚置好的空闲
    // 又顶回「进行中」，而且之后不会再有 turn/end 来收尾 —— 按钮就永久卡住。
    if (!_turnClosed) state.setAgentRunning(true);

    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        content: _messages[idx].content + text,
      );
    } else {
      state.setActiveTool(null);
      _messages.add(ChatMessage(
        id: 'stream-${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: text,
        isStreaming: true,
      ));
    }
    state.notify();
    onScrollToBottom?.call();
  }

  /// `assistant/message` 定稿后的收尾
  ///
  /// Web 端的防双渲染是「扣住再放行」：durable 消息先落到 pending，
  /// 等 assistant-stream 的 `end` 帧点名同一 seq 才发布。
  /// 这里用等价做法 —— 定稿即整体替换那条 streaming 气泡，并结束打字机态。
  ///
  /// [interrupted] 为真表示被停止，Web 端显示「已停止」而不是错误。
  void onAssistantFinal(String text, bool interrupted) {
    if (text.isEmpty) {
      // 空定稿：可能只是占位，别把已有内容抹掉
      state.setAssistantStreaming(false);
      return;
    }
    onAssistantMessage(text);
    state.setAssistantStreaming(false);
    if (interrupted) state.setLastTurnEnd(DateTime.now());
  }

  void onAssistantMessage(String text) {
    _touchActivity();
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _deltaBuffer.clear();

    state.setAssistantStreaming(false);
    state.setActiveTool(null);

    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(content: text, isStreaming: false);
    } else {
      final lastAssistant = _messages.lastIndexWhere((m) => m.role == 'assistant');
      final existing = lastAssistant >= 0 ? _messages[lastAssistant].content : '';
      if (lastAssistant >= 0 &&
          (existing == text || (existing.isNotEmpty && text.startsWith(existing)))) {
        _messages[lastAssistant] = _messages[lastAssistant].copyWith(
          content: text,
          isStreaming: false,
        );
      } else {
        _messages.add(ChatMessage(
          id: 'a-${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: text,
        ));
      }
    }
    state.notify();
    onScrollToBottom?.call();
  }

  void onUserMessage(String text, String? rpcId, String seq) {
    // 先按 rpcId 对账：本地乐观气泡就地转为确认态，不新增第二条
    if (rpcId != null && _pendingEcho.containsKey(rpcId)) {
      _reconcileEcho(rpcId, text);
      final key = 'u$seq';
      if (seq.isNotEmpty) _seenUserSeq.add(key);
      _touchActivity();
      state.notify();
      return;
    }

    final key = 'u$seq';
    if (seq.isNotEmpty && !_seenUserSeq.add(key)) return;

    // 内容去重：如果最后一条用户消息内容相同，跳过
    if (_messages.isNotEmpty &&
        _messages.last.role == 'user' &&
        _messages.last.content == text) {
      return;
    }

    _touchActivity();
    // 用户发了新消息 = 新一轮的开始。
    // 必须在这里重新武装运行态：本轮消息可能被客户端去重（同内容、
    // 同 seq）而跳过下面那行，但用户的心智模型是「我一发，它就又在跑了」。
    _turnClosed = false;
    _messages.add(ChatMessage(
      id: key.isEmpty ? 'u-${DateTime.now().millisecondsSinceEpoch}' : key,
      role: 'user',
      content: text,
    ));
    state.notify();
    onScrollToBottom?.call();
  }

  void onToolCall(String toolName, [String? arguments]) {
    _touchActivity();
    // 参数是未解析的 JSON 字符串，抽一个能看懂的摘要放进状态栏
    state.setActiveTool(_toolSummary(toolName, arguments));
    state.setAgentRunning(true);
  }

  /// 从工具参数里抽一行摘要（命令 / 路径）
  String _toolSummary(String toolName, String? rawArguments) {
    final detail = extractToolDetail(rawArguments);
    return detail == null || detail.isEmpty ? toolName : '$toolName · $detail';
  }

  void onToolResult() {
    state.setActiveTool(null);
  }

  /// `api-session/status` / control 流的运行状态推送
  ///
  /// 写入权威中枢，并顺带修正当前会话的 agentRunning，
  /// 避免轮询（8s）造成的状态滞后。
  ///
  /// **`running: true` 必须受 [_turnClosed] 约束。** 这条通道是
  /// `$events` 的 emit，重连时 Host 会把当前状态重放一遍；如果本轮的
  /// `turn/end` 已经处理过（`_turnClosed == true`），此时再来的
  /// `running: true` 是**上一轮的残留**，不是新一轮 —— 真正的新一轮会先发
  /// `turn/start`，那时 [_turnClosed] 已被清掉。
  ///
  /// 不设这道闸，重连一次就会把已收尾的会话顶成「进行中」，
  /// 而且之后不会再有 `turn/end` 来收尾，按钮就永久卡住。
  void onSessionStatus(String sessionId, bool running) {
    state.updateSessionStatus(sessionId, running);
    if (sessionId == state.sessionId) {
      if (!running || !_turnClosed) {
        state.setAgentRunning(running);
      }
    }
    onSessionStatusExternal?.call(sessionId, running);
  }

  void onToolView(ToolViewRecord rec) {
    _touchActivity();
    state.applyToolView(
      diffs: rec.diffs,
      title: rec.title,
      done: rec.done,
      turn: rec.turn,
    );
  }

  /// 新一轮开始：重新武装运行态
  ///
  /// `turn/end` 会把运行态置空闲，但排队消息会让同一轮继续。
  /// Host 的 `api-session/status` 只在**状态变化**时推送，所以不能依赖它
  /// 把 running 从 false 拉回 true —— 这里用 journal 的 `turn/start` 兜底。
  void onTurnStart() {
    _touchActivity();
    _turnClosed = false;
    state.setAgentRunning(true);
    state.notify();
  }

  void onTurnEnd() {
    _turnClosed = true;
    // 只清当前会话的待办：别的会话的审批/提问不该被本轮结束牵连
    final sid = state.sessionId;
    for (final a in state.approvals.where((a) => a.sessionId == sid).toList()) {
      state.removeApproval(a.approvalId);
    }
    for (final q in state.allQuestions.where((q) => q.sessionId == sid).toList()) {
      state.removeQuestion(q.rpcId);
    }
    if (state.questionDialogOpen) {
      state.setQuestionDialogOpen(false);
      onPopQuestionDialog?.call();
    }
    state.setAgentRunning(false);
    state.setAssistantStreaming(false);
    state.setActiveTool(null);
    state.setLastTurnEnd(DateTime.now());

    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(isStreaming: false);
    }
    state.notify();
  }

  /// 审批到达。
  ///
  /// 声音 + 系统通知挂在**这里**（而不是各后端的接线里）：
  /// 两个后端行为天然一致，接第三个后端时白拿。
  void onApproval({
    required String rpcId,
    required String sessionId,
    required String approvalId,
    required String toolName,
    String? reason,
  }) {
    state.addApproval(PendingApproval(
      rpcId: rpcId,
      sessionId: sessionId,
      approvalId: approvalId,
      toolName: toolName,
      reason: reason,
    ));
    _touchActivity();
    SoundService.approval();
    NotificationService.show(
      id: 30000,
      title: '需要确认',
      body: '工具 $toolName 需要确认',
    );
  }

  void onApprovalResolved(String approvalId) {
    state.removeApproval(approvalId);
  }

  /// 提问到达（opencode 表单 v1 不在范围，钩子后端无关，接表单时白拿）
  void onQuestion({
    required String rpcId,
    required String sessionId,
    required List<Map<String, dynamic>> questions,
  }) {
    state.addQuestion(PendingQuestion(
      rpcId: rpcId,
      sessionId: sessionId,
      questions: questions,
    ));
    _touchActivity();
    SoundService.question();
    // 切到后台时提问也要弹通知，否则最小化时看不到提问
    if (!AppVisibility.foreground) {
      NotificationService.show(
        id: 30001,
        title: 'DSH 向你提问',
        body: questions.map((q) => q['question']).whereType<String>().join(' '),
      );
    }
    // 非当前会话的提问不入弹窗：Web 端只在侧栏显示告警点，落选者留在队列里
    if (state.sessionId == sessionId) {
      onShowQuestionDialog?.call();
    }
  }

  void onQuestionResolved(String rpcId) {
    final wasShown = state.question?.rpcId == rpcId && state.questionDialogOpen;
    state.removeQuestion(rpcId);
    if (wasShown && state.questionDialogOpen) {
      state.setQuestionDialogOpen(false);
      onPopQuestionDialog?.call();
    }
  }

  // ── opencode 表单（与提问对称：声音 / 通知 / 弹窗钩子） ──

  /// 表单待回答（opencode 轮询对账发现 pending form 时调用）
  void onForm(PendingForm form) {
    state.addForm(form);
    _touchActivity();
    SoundService.question();
    if (!AppVisibility.foreground) {
      NotificationService.show(
        id: 30002,
        title: 'opencode 表单待填写',
        body: form.title,
      );
    }
    // 非当前会话的表单不入弹窗：只留在队列里，等用户切过去
    if (state.sessionId == form.sessionId) {
      onShowFormDialog?.call();
    }
  }

  /// 表单已被解决（取消事件 / 应答成功 / 对账发现已消失）
  void onFormResolved(String formId) {
    final wasShown = state.form?.formId == formId && state.formDialogOpen;
    state.removeForm(formId);
    if (wasShown && state.formDialogOpen) {
      state.setFormDialogOpen(false);
      onPopFormDialog?.call();
    }
  }

  void onQueueUpdate(List<Map<String, dynamic>> queueItems) {
    // 队列更新，暂不处理
  }

  void onWorkspaceBaseline(List<String> archivedSessionIds) {
    state.setArchivedIds(Set.from(archivedSessionIds));
  }

  void onControlBaseline(Map<String, dynamic> baseline) {
    // 控制基线，暂不处理
  }

  void onProjectionChange(String sessionId, String key, dynamic value) {
    // 只关心当前会话的模型选择投影，其余投影暂不消费
    if (key != 'modelSelection') return;
    if (sessionId != state.sessionId) return;
    state.setModelSelection(ModelSelection.fromProjection(value));
  }

  /// 开窗快照里的投影（`{values: {...}}`）
  ///
  /// 重连后靠它恢复当前模型；不处理的话切换过模型也会显示成默认值。
  void applySnapshotProjections(Map<String, dynamic> projections) {
    final values = projections['values'];
    if (values is! Map) return;
    final selection = ModelSelection.fromProjection(values['modelSelection']);
    if (selection != null) state.setModelSelection(selection);
  }

  // ── 重置 ────────────────────────────────────────

  void reset() {
    _deltaBuffer.clear();
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _turnClosed = false;
    _messages.clear();
    _seenUserSeq.clear();
    _pendingEcho.clear();
  }

  void dispose() {
    _deltaFlushTimer?.cancel();
  }
}
