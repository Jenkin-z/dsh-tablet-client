import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_controller.dart';
import '../services/session_state.dart';
import '../services/model_catalog.dart';
import '../services/server_manager.dart';
import '../services/session_router.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../utils/constants.dart';
import '../widgets/approval_card.dart';
import '../widgets/chat_approval_list.dart';
import '../widgets/chat_app_bar_actions.dart';
import '../widgets/chat_app_bar_title.dart';
import '../widgets/chat_disconnect_banner.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_question_prompt.dart';
import '../widgets/changes_drawer.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/model_sheet.dart';
import '../widgets/open_code_form_host.dart';
import '../widgets/question_sheet.dart';
import '../widgets/session_drawer.dart';
import '../widgets/tool_status_bar.dart';

/// 聊天主界面：会话侧栏 + Markdown 对话 + 流式展示
///
/// 重构后：所有状态都从 SessionState 读取，不再自己维护状态。
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
  /// 正在请求停止（防止重复点击，不代表已停止）
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _ctrl = ChatController(
      settings: context.read<SettingsService>(),
      manager: context.read<ServerManager>(),
      // 使用全局唯一的状态中枢，控制台等页面读同一实例
      state: context.read<SessionState>(),
    );
    _ctrl
      ..dispatcher.onScrollToBottom = _scrollToBottom
      ..dispatcher.onJumpToLatest = _jumpToLatest
      ..dispatcher.onShowQuestionDialog = _maybeShowQuestionDialog
      ..dispatcher.onPopQuestionDialog = () {
        if (mounted) Navigator.of(context).maybePop();
      }
      ..dispatcher.onShowSnackBar = (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      };
    _ctrl.state.addListener(_onStateUpdate);
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

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  void _onRouteRequest() {
    final router = _router;
    if (router == null || !mounted) return;
    final target = router.sessionId;
    final serverId = router.serverId;
    if (target == null || serverId == null) return;
    // 只处理「同一台机器内换会话」。跨机器的切换由 MainShell 改
    // activeServerId 完成，那次会重建本 widget 并重新 boot()；
    // 这里若再切一次，同一件事就做了两遍（竞态来源）。
    if (serverId != _ctrl.settings.activeServerId) {
      router.consume(router.token);
      return;
    }
    if (target == _ctrl.state.sessionId && _ctrl.state.connected) {
      router.consume(router.token);
      return;
    }
    _ctrl.switchSession(target);
    router.consume(router.token);
  }

  void _onMonitorTick() {
    // 监控 tick，暂不处理
  }

  @override
  void dispose() {
    _router?.removeListener(_onRouteRequest);
    _manager?.removeListener(_onMonitorTick);
    _ctrl.state.removeListener(_onStateUpdate);
    _ctrl.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── 滚动控制 ────────────────────────────────────

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
    final q = _ctrl.state.question;
    if (q == null || _ctrl.state.questionDialogOpen || !mounted) return;
    if (q.sessionId != _ctrl.state.sessionId) {
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
    _ctrl.state.setQuestionDialogOpen(true);
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuestionSheet(
        question: q,
        onSubmit: _submitQuestion,
      ),
    ).then((submitted) {
      _ctrl.state.setQuestionDialogOpen(false);
      // 未提交即关闭 → 按 Web 端语义显式取消，不能让 Host 一直挂等
      if (submitted != true) {
        _ctrl.cancelQuestion();
      }
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
    if (!_ctrl.state.connected) {
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

  /// 停止当前运行 —— **不做乐观更新**
  ///
  /// Web 端语义（InputBar.tsx:283 及其测试）：只有 RPC 返回 `{accepted:true}`，
  /// 界面不得自己把 running 翻成 false，也不清空已流出的文字；
  /// 必须等 Host 推来的权威 `running:false` / `turn/end`。
  /// 失败就把错误说出来。
  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    try {
      await _ctrl.cancel();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('停止失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
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

  /// 打开模型切换面板
  ///
  /// 面板返回选中的模型后回写状态，让标题栏立刻反映新值；
  /// Host 随后推来的 `modelSelection` 投影仍是权威值。
  Future<void> _openModelSheet() async {
    final service = _ctrl.models;
    final sessionId = _ctrl.state.sessionId;
    if (service == null || sessionId == null || !_ctrl.state.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接，无法切换模型')),
      );
      return;
    }
    final picked = await showModalBottomSheet<ModelSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ModelSheet(
        service: service,
        sessionId: sessionId,
        current: _ctrl.state.modelSelection,
      ),
    );
    if (picked == null || !mounted) return;
    _ctrl.state.setModelSelection(picked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换到 ${picked.label}')),
    );
  }

  /// 有待回答的问题时给一条入口（弹窗被关掉后还能再打开）
  Widget _questionPrompt() {
    return ChatQuestionPrompt(
      ctrl: _ctrl,
      onPressed: _maybeShowQuestionDialog,
    );
  }

  /// AppBar 标题：连接状态点 + 当前会话名（保持原语义，未做任何改动）
  Widget _appBarTitle() {
    return ChatAppBarTitle(
      title: _ctrl.settings.active == null
          ? 'DSH Agent'
          : _ctrl.state.sessionTitle,
    );
  }

  // ── 构建 ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessionId = _ctrl.state.sessionId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: isDark ? const Color(0xFF000000) : IosTheme.iosGroupedBg,
      appBar: AppBar(
        title: _appBarTitle(),
        actions: [
          ChatAppBarActions(
            agentRunning: _ctrl.state.agentRunning,
            stopping: _stopping,
            pendingCount: _ctrl.state.changes.pendingCount,
            connected: _ctrl.state.connected,
            onStop: _stop,
            onOpenChanges: _openChanges,
            onBoot: _ctrl.boot,
            onOpenModelSheet: _openModelSheet,
          ),
        ],
      ),
      drawer: SessionDrawer(
        sessions: _ctrl.state.visibleSessions,
        serverId: _ctrl.settings.activeServerId ?? '',
        activeId: sessionId,
        loading: _ctrl.state.loadingSessions,
        onRefresh: () => _ctrl.boot(),
        onCreateUngrouped: () {
          Navigator.of(context).maybePop();
          _ctrl.createNewSession();
        },
        onCreateInWorkspace: (cwd) {
          Navigator.of(context).maybePop();
          _ctrl.createNewSession(cwd: cwd);
        },
        onSelectSession: _switchSession,
        // 其它会话有待办时在列表上显示告警点（Web 端的跨会话唯一提示方式）
        pendingKindOf: _ctrl.state.pendingKindOf,
      ),
      endDrawer: ChangesDrawer(tracker: _ctrl.state.changes),
      body: Column(
        children: [
          // 断线横幅：重构时丢了，导致断线后页面一句话都不说
          if (!_ctrl.state.connected)
            ChatDisconnectBanner(retrying: _ctrl.settings.autoReconnect),
          if (_ctrl.state.activeTool != null)
            ToolStatusBar(toolName: _ctrl.state.activeTool!),
          _questionPrompt(),
          // opencode 表单（自挂 dispatcher 回调 + 入口条）
          OpenCodeFormHost(ctrl: _ctrl),
          Expanded(
            child: _buildMessages(),
          ),
          // 只展示当前会话的审批；其它会话的审批在侧栏以告警点提示（同 Web 端）
          ChatApprovalList(
            approvals: _ctrl.state.approvals,
            sessionId: sessionId,
            onAnswer: _answerApproval,
            onViewSession: (a) => _switchSession(a.sessionId),
          ),
          ChatInputBar(
            controller: _inputController,
            connected: _ctrl.state.connected,
            running: _ctrl.state.agentRunning,
            onSend: _send,
            onStop: _stop,
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildMessages() {
    return ChatMessageList(
      scrollController: _scrollController,
      messages: _ctrl.dispatcher.messages,
    );
  }
}