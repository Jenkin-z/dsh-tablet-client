import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_controller.dart';
import '../services/server_manager.dart';
import '../services/session_router.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../utils/constants.dart';
import '../widgets/approval_card.dart';
import '../widgets/changes_drawer.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/question_sheet.dart';
import '../widgets/session_drawer.dart';
import '../widgets/tool_status_bar.dart';

/// 聊天主界面：会话侧栏 + Markdown 对话 + 流式展示
///
/// 业务逻辑委托给 ChatController，本类仅负责 UI 编排。
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late final ChatController _ctrl;
  SessionRouter? _router;
  ServerManager? _manager;

  @override
  void initState() {
    super.initState();
    _ctrl = ChatController(
      settings: context.read<SettingsService>(),
      manager: context.read<ServerManager>(),
    );
    _ctrl
      ..onScrollToBottom = _scrollToBottom
      ..onJumpToLatest = _jumpToLatest
      ..onShowQuestionDialog = _maybeShowQuestionDialog
      ..onPopQuestionDialog = () {
        if (mounted) Navigator.of(context).maybePop();
      }
      ..onShowSnackBar = (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      };
    _ctrl.addListener(_onControllerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.boot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router == null) {
      _router = Provider.of<SessionRouter>(context, listen: false);
      _router!.addListener(_onRouteRequest);
    }
    if (_manager == null) {
      _manager = Provider.of<ServerManager>(context, listen: false);
      _manager!.addListener(_onMonitorTick);
    }
  }

  void _onRouteRequest() {
    final router = _router;
    if (router == null || !mounted) return;
    final target = router.sessionId;
    final serverId = router.serverId;
    if (target == null || serverId == null) return;
    if (serverId != _ctrl.settings.activeServerId) return;
    if (target == _ctrl.muxSessionId && _ctrl.connected) {
      router.consume(router.token);
      return;
    }
    if (!router.consume(router.token)) return;
    _switchSession(target);
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _onMonitorTick() => _ctrl.onMonitorTick();

  @override
  void dispose() {
    _router?.removeListener(_onRouteRequest);
    _manager?.removeListener(_onMonitorTick);
    _ctrl.removeListener(_onControllerUpdate);
    _ctrl.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── 滚动控制 ────────────────────────────────────

  /// reverse ListView：pixels == 0 就是最新消息。
  /// 进会话时 ListView 可能还没挂上，Markdown 也会晚一帧撑高，所以连跳几帧。
  void _jumpToLatest([int left = jumpToLatestFrames]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || left <= 0) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _jumpToLatest(left - 1);
    });
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      // reverse：离最新超过阈值视为在看历史，不抢滚
      if (!force && pos.pixels > scrollIdleThreshold) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ── 会话操作 ────────────────────────────────────

  void _switchSession(String sessionId) {
    Navigator.of(context).maybePop();
    _ctrl.switchSession(sessionId);
  }

  void _createNewSession({String? cwd}) {
    Navigator.of(context).maybePop();
    _ctrl.createNewSession(cwd: cwd);
  }

  // ── 审批 / 问题 ─────────────────────────────────

  Future<void> _answerApproval(PendingApproval a, bool allow) async {
    final ok = await _ctrl.answerApproval(a, allow);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回答未被接受，可能已过期')),
      );
    }
  }

  void _maybeShowQuestionDialog() {
    final q = _ctrl.question;
    if (q == null || _ctrl.questionDialogOpen || !mounted) return;
    if (q.sessionId != _ctrl.settings.sessionId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('其他会话有问题待回答'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => _switchSession(q.sessionId),
          ),
        ),
      );
      return;
    }
    _ctrl.questionDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuestionSheet(
        question: q,
        onSubmit: _submitQuestion,
      ),
    ).then((_) {
      _ctrl.questionDialogOpen = false;
    });
  }

  Future<void> _submitQuestion(List<Map<String, dynamic>> answers) async {
    final ok = await _ctrl.submitQuestion(answers);
    if (!ok) {
      throw Exception('not accepted');
    }
  }

  // ── 发送 / 取消 ─────────────────────────────────

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (!_ctrl.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接，消息已保留')),
      );
      return;
    }
    _inputController.clear();
    _scrollToBottom(force: true);
    try {
      await _ctrl.send(text);
    } catch (e) {
      if (!mounted) return;
      _inputController.text = text;
      _inputController.selection = TextSelection.collapsed(offset: text.length);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    }
  }

  Future<void> _cancel() async {
    await _ctrl.cancel();
  }

  void _openChanges() {
    final state = _scaffoldKey.currentState;
    if (state == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开变更')),
      );
      return;
    }
    state.openEndDrawer();
  }

  // ── 构建 ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessionId = _ctrl.settings.sessionId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: isDark ? const Color(0xFF000000) : IosTheme.iosGroupedBg,
      appBar: AppBar(
        title: Row(
          children: [
            _buildStatusDot(),
            const SizedBox(width: IosTheme.spaceS),
            Expanded(
              child: Text(
                _ctrl.settings.active == null
                    ? _ctrl.currentTitle
                    : '${_ctrl.settings.active!.name} · ${_ctrl.currentTitle}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_ctrl.agentRunning)
            IconButton(
              icon: _ctrl.canceling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined, size: 22),
              tooltip: _ctrl.canceling ? '正在停止' : '停止',
              onPressed: _ctrl.canceling ? null : _cancel,
            ),
          IconButton(
            icon: Badge(
              label: Text('${_ctrl.changes.items.length}'),
              isLabelVisible: _ctrl.changes.items.isNotEmpty,
              child: const Icon(Icons.difference_outlined, size: 22),
            ),
            tooltip: '变更',
            onPressed: _ctrl.connected ? _openChanges : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: '重连',
            onPressed: _ctrl.boot,
          ),
        ],
      ),
      drawer: SessionDrawer(
        sessions: _ctrl.visibleSessions,
        serverId: _ctrl.settings.active?.id ?? '',
        activeId: sessionId,
        loading: _ctrl.loadingSessions,
        onRefresh: _ctrl.refreshSessions,
        onCreateUngrouped: () => _createNewSession(),
        onCreateInWorkspace: (cwd) => _createNewSession(cwd: cwd),
        onSelectSession: _switchSession,
      ),
      endDrawer: ChangesDrawer(tracker: _ctrl.changes),
      body: Column(
        children: [
          if (!_ctrl.connecting && !_ctrl.connected) _disconnectBanner(),
          Expanded(child: _buildBody()),
          if (_ctrl.activeTool != null)
            ToolStatusBar(toolName: _ctrl.activeTool!),
          ..._buildPendingCards(sessionId),
          ChatInputBar(
            controller: _inputController,
            connected: _ctrl.connected,
            sending: _ctrl.sending,
            onSend: _send,
          ),
        ],
      ),
      ),
    );
  }

  Widget _disconnectBanner() {
    final retrying = _ctrl.settings.autoReconnect;
    return Material(
      color: IosTheme.iosOrange.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceS,
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 18, color: IosTheme.iosOrange),
            const SizedBox(width: IosTheme.spaceS),
            Expanded(
              child: Text(
                retrying ? '连接中断，正在重连…' : '已断开，自动重连已关闭',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPendingCards(String? sessionId) {
    final cards = <Widget>[];
    final mine =
        _ctrl.approvals.where((a) => a.sessionId == sessionId).toList();
    final foreign =
        _ctrl.approvals.where((a) => a.sessionId != sessionId).toList();
    for (final a in [...mine, ...foreign]) {
      cards.add(ApprovalCard(
        approval: a,
        isForeignSession: a.sessionId != sessionId,
        onAnswer: (allow) => _answerApproval(a, allow),
        onViewSession: () => _switchSession(a.sessionId),
      ));
    }
    final q = _ctrl.question;
    if (q != null &&
        q.sessionId == sessionId &&
        !_ctrl.questionDialogOpen) {
      cards.add(
        Container(
          margin: const EdgeInsets.fromLTRB(
            IosTheme.spaceL,
            IosTheme.spaceXS,
            IosTheme.spaceL,
            0,
          ),
          child: IosButton(
            label: '有 ${q.questions.length} 个问题待回答',
            icon: Icons.help_outline,
            filled: false,
            onPressed: _maybeShowQuestionDialog,
          ),
        ),
      );
    }
    return cards;
  }

  Widget _buildStatusDot() {
    final color = !_ctrl.connected
        ? IosTheme.iosRed
        : _ctrl.agentRunning
            ? IosTheme.iosOrange
            : IosTheme.iosGreen;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_ctrl.connecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 2,
              color: IosTheme.iosBlue,
            ),
            const SizedBox(height: IosTheme.spaceL),
            Text(
              '正在连接 DSH…',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: IosTheme.iosGray,
              ),
            ),
          ],
        ),
      );
    }
    if (_ctrl.error != null && _ctrl.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(IosTheme.spaceXXXL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 56,
                color: IosTheme.iosGray2,
              ),
              const SizedBox(height: IosTheme.spaceL),
              Text(
                _ctrl.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: IosTheme.iosGray,
                ),
              ),
              const SizedBox(height: IosTheme.spaceXXL),
              IosButton(
                label: '重试',
                onPressed: _ctrl.boot,
              ),
            ],
          ),
        ),
      );
    }
    if (_ctrl.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: IosTheme.iosGray3,
            ),
            const SizedBox(height: IosTheme.spaceM),
            Text(
              '开始和 Agent 对话吧',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: IosTheme.iosGray,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
        vertical: IosTheme.spaceS,
        horizontal: IosTheme.spaceS,
      ),
      itemCount: _ctrl.messages.length,
      itemBuilder: (context, i) => MessageBubble(
        message: _ctrl.messages[_ctrl.messages.length - 1 - i],
      ),
    );
  }
}
