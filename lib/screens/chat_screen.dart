import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/changes_tracker.dart';import '../services/dsh_api.dart';
import '../services/mux_stream.dart';
import '../services/session_router.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../utils/session_format.dart';
import '../widgets/approval_card.dart';
import '../widgets/changes_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/question_sheet.dart';

/// 聊天主界面：会话侧栏 + Markdown 对话 + 流式展示
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();

  DshApi? _api;
  MuxStream? _mux;

  final List<DshMessage> _messages = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _workspaces = [];
  Set<String> _archivedIds = {};
  String _currentTitle = 'DSH Agent';
  bool _connecting = true;
  bool _connected = false;
  bool _sending = false;
  bool _agentRunning = false;
  bool _loadingSessions = false;
  String? _error;
  String? _activeTool;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  // 回声去重：自己发出的 prompt 的 rpcId；已见过的 user seq（历史+实时）
  final Set<String> _pendingEchoRpc = {};
  final Set<String> _seenUserSeq = {};
  String? _lastSentText;
  DateTime? _lastSentAt;
  // 变更 / 审批 / 问题
  final ChangesTracker _changes = ChangesTracker();
  final List<PendingApproval> _approvals = [];
  PendingQuestion? _question;
  bool _questionDialogOpen = false;
  static const String _ungroupedKey = '_ungrouped';
  SessionRouter? _router;
  Timer? _approvalPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅控制台的“打开会话”意图（只绑定一次）
    if (_router == null) {
      _router = Provider.of<SessionRouter>(context, listen: false);
      _router!.addListener(_onRouteRequest);
    }
  }

  void _onRouteRequest() {
    final router = _router;
    if (router == null || !mounted) return;
    final target = router.target;
    if (target == null || target == _settings.sessionId) return;
    if (!router.consume(router.token)) return;
    _switchSession(target);
  }

  @override
  void dispose() {
    _router?.removeListener(_onRouteRequest);
    _reconnectTimer?.cancel();
    _deltaFlushTimer?.cancel();
    _approvalPollTimer?.cancel();
    _mux?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  SettingsService get _settings =>
      Provider.of<SettingsService>(context, listen: false);

  // ---------- 启动流程 ----------

  Future<void> _boot() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    _api = DshApi(baseUrl: _settings.serverUrl);

    final ok = await _api!.testConnection();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _connecting = false;
        _connected = false;
        _error = '连接失败: ${_settings.serverUrl}\n请检查 PC 端 DSH 是否启动、同一局域网。';
      });
      _scheduleReconnect();
      return;
    }

    try {
      String? sessionId = _settings.sessionId;
      if (sessionId != null) {
        final valid = await _validateSession(sessionId);
        if (!valid) sessionId = null;
      }
      sessionId ??= await _api!.createSession();
      await _settings.setSessionId(sessionId);
      await _settings.markSeen(sessionId);

      await _refreshSessions();
      await _loadHistory(sessionId);
      _connectMux(sessionId);

      setState(() {
        _connecting = false;
        _connected = true;
        _error = null;
      });
      _reconnectAttempts = 0;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _error = '初始化失败: $e';
      });
      _scheduleReconnect();
    }
  }

  Future<bool> _validateSession(String sessionId) async {
    try {
      await _api!.getHistory(sessionId, maxMessages: 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshSessions() async {
    if (_api == null) return;
    setState(() => _loadingSessions = true);
    try {
      final items = await _api!.listSessions();
      Map<String, dynamic>? ws;
      try {
        ws = await _api!.listWorkspaces();
      } catch (_) {
        ws = null; // 老版本/无工作区部署：退化为平铺
      }
      if (!mounted) return;
      setState(() {
        _sessions = items;
        if (ws != null) {
          final rawItems = ws['items'] as List<dynamic>? ?? [];
          _workspaces =
              rawItems.whereType<Map<String, dynamic>>().toList();
          final rawArchived = ws['archivedSessionIds'] as List<dynamic>? ?? [];
          _archivedIds = rawArchived.whereType<String>().toSet();
        }
        _currentTitle = _titleFor(_settings.sessionId);
      });
      _expandGroupOf(_settings.sessionId);
    } catch (_) {
      // 侧栏刷新失败不影响对话
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  String _titleFor(String? sessionId) {
    if (sessionId == null) return 'DSH Agent';
    for (final s in _sessions) {
      if (s['sessionId'] == sessionId) return sessionTitleOf(s);
    }
    return 'DSH Agent';
  }

  /// 当前会话所在的工作区分组自动展开（默认全收起）
  void _expandGroupOf(String? sessionId) {
    if (sessionId == null) return;
    String group = _ungroupedKey;
    for (final w in _workspaces) {
      final ids = (w['sessionIds'] as List<dynamic>? ?? []).whereType<String>();
      if (ids.contains(sessionId)) {
        group = w['workspaceId'] as String? ?? _ungroupedKey;
        break;
      }
    }
    if (!_settings.expandedWs.contains(group)) {
      _settings.setWsExpanded(group, true);
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadHistory(String sessionId) async {
    final result = await _api!.getHistory(sessionId, maxMessages: 50);
    final entries = result['events'] as List<dynamic>? ?? [];
    final parsed = MuxStream.parseHistory(entries);
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _seenUserSeq.clear();
      for (final p in parsed) {
        _messages.add(DshMessage(id: p.id, role: p.role, content: p.text));
        _seenUserSeq.add(p.id);
      }
      // 历史回填变更栏
      _changes.clear();
      for (final v in MuxStream.parseHistoryViews(entries)) {
        _changes.applyView(
            diffs: v.diffs, title: v.title, done: v.done, turn: v.turn);
      }
    });
    // 等列表布局完成后再跳到底（进会话/切换会话直达最新）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  /// 切换会话：换 mux 订阅 + 重载历史
  Future<void> _switchSession(String sessionId) async {
    if (sessionId == _settings.sessionId && _connected) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).maybePop();
    await _settings.setSessionId(sessionId);
    await _settings.markSeen(sessionId);
    setState(() {
      _messages.clear();
      _activeTool = null;
      _agentRunning = false;
      _currentTitle = _titleFor(sessionId);
      _pendingEchoRpc.clear();
      _lastSentText = null;
      _lastSentAt = null;
      _changes.clear();
    });
    _expandGroupOf(sessionId);
    try {
      await _loadHistory(sessionId);
      _connectMux(sessionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换会话失败: $e')),
      );
    }
    // 切过来的会话若有待回答问题，弹出表单
    _maybeShowQuestionDialog();
  }

  /// 新建会话并切过去；指定 workspaceId 则归属该工作区
  Future<void> _createNewSession({String? workspaceId}) async {
    Navigator.of(context).maybePop();
    if (_api == null || !_connected) return;
    try {
      final id = await _api!.createSession(workspaceId: workspaceId);
      await _refreshSessions();
      await _switchSession(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新建会话失败: $e')),
      );
    }
  }

  void _connectMux(String sessionId) {
    _mux?.dispose();
    final mux = MuxStream(wsBaseUrl: _settings.wsUrl);
    mux.sessionId = sessionId;
    mux.onTextDelta = _onDelta;
    mux.onAssistantMessage = _onAssistantFinal;
    mux.onUserMessage = _onUserMessage;
    mux.onToolView = _onToolView;
    mux.onApproval = _onApproval;
    mux.onApprovalResolved = _onApprovalResolved;
    mux.onQuestion = _onQuestion;
    mux.onQuestionResolved = _onQuestionResolved;
    mux.onToolCall = (name) => setState(() => _activeTool = name);
    mux.onTurnEnd = () {
      setState(() {
        _agentRunning = false;
        _activeTool = null;
        // 轮次结束：清掉所有待处理审批/问题（PC 端已处理则卡消失；mux 收到 resolved 的也清了，无副作用）
        _approvals.clear();
        _question = null;
        if (_questionDialogOpen) {
          _questionDialogOpen = false;
          Navigator.of(context).maybePop();
        }
      });
      final idx = _messages.indexWhere((m) => m.isStreaming);
      if (idx >= 0) {
        setState(() => _messages[idx] = _messages[idx].copyWith(isStreaming: false));
      }
      // 完成提示音
      if (_settings.soundEnabled && _settings.completionSound) {
        SoundService.done(customPath: _settings.customSoundPath('done'));
      }
      // 标题可能更新了（首轮后自动生成），顺手刷一下侧栏
      _refreshSessions();
    };
    mux.onDisconnected = () {
      if (!mounted) return;
      setState(() => _connected = false);
      _scheduleReconnect();
    };
    mux.connect();
    setState(() => _connected = true);
    _mux = mux;
    // 启动审批轮询：每 5 秒检查一次，兜底 mux 事件丢失的情况
    _approvalPollTimer?.cancel();
    _approvalPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkApprovalsStale();
    });
  }

  /// 轻量兜底：如果 approval/question 在列表中但 mux 已不推 resolved，
  /// turn/end 已清过了（上层），这里处理"turn/end 没到但 approval 确实已解决"的边缘情况
  void _checkApprovalsStale() {
    if (!mounted || !_connected || _api == null) return;
    final sid = _settings.sessionId;
    if (sid == null) return;
    // 无待处理审批时跳过查询
    if (_approvals.isEmpty && _question == null) return;
    _api!.getHistory(sid, maxMessages: 10).then((result) {
      if (!mounted) return;
      final events = result['events'] as List<dynamic>? ?? [];
      // 如果最近一条是 turn/start 或 assistant，说明 agent 已在跑——清掉过期审批
      for (final e in events) {
        final ev = e as Map<String, dynamic>? ?? {};
        final event = ev['event'] as Map<String, dynamic>?;
        final type = event?['type'] as String? ?? '';
        if (type == 'turn/start' || type == 'assistant/message') {
          // agent 已在跑或已回复：上一次的审批肯定已解决
          if (_approvals.isNotEmpty || _question != null) {
            setState(() {
              _approvals.clear();
              _question = null;
            });
          }
          return;
        }
      }
    }).catchError((_) {});
  }

  void _scheduleReconnect() {
    if (!_settings.autoReconnect || !mounted) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts > 5 ? 30 : _reconnectAttempts * 3);
    _reconnectTimer = Timer(delay, () {
      if (mounted) _boot();
    });
  }

  // ---------- 流式事件 ----------

  // 增量合并：120ms 一批，避免逐字 setState 重排整个 Markdown
  String _deltaBuffer = '';
  Timer? _deltaFlushTimer;

  void _onDelta(String delta) {
    if (!mounted) return;
    _touchActivity();
    _deltaBuffer += delta;
    _deltaFlushTimer ??=
        Timer(const Duration(milliseconds: 120), _flushDelta);
  }

  void _flushDelta() {
    _deltaFlushTimer = null;
    if (!mounted) return;
    final text = _deltaBuffer;
    _deltaBuffer = '';
    if (text.isEmpty) return;
    final idx = _messages.indexWhere((m) => m.isStreaming);
    // 轮次已结束且无流式气泡：迟到的尾巴直接丢弃（防另起一条）
    if (idx < 0 && !_agentRunning) return;
    setState(() {
      _agentRunning = true;
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(
          content: _messages[idx].content + text,
        );
      } else {
        _activeTool = null;
        _messages.add(DshMessage(
          id: 'stream-${_uuid.v4()}',
          role: 'assistant',
          content: text,
          isStreaming: true,
        ));
      }
    });
    _scrollToBottom();
  }

  void _onAssistantFinal(String text) {
    if (!mounted) return;
    _touchActivity();
    // 最终全文为准，丢弃未刷新的增量尾巴（同帧顺序保证不丢字）
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _deltaBuffer = '';
    setState(() {
      final idx = _messages.indexWhere((m) => m.isStreaming);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(content: text);
      } else {
        _messages.add(DshMessage(
          id: 'a-${_uuid.v4()}',
          role: 'assistant',
          content: text,
        ));
      }
    });
    _scrollToBottom();
  }

  /// mux 推来的 user/message：自己发的回声去重，他端发的追加显示
  void _onUserMessage(String text, String? rpcId, String seq) {
    if (!mounted) return;
    final key = 'u$seq';
    if (seq.isNotEmpty && !_seenUserSeq.add(key)) return; // 已展示过
    if (rpcId != null && _pendingEchoRpc.remove(rpcId)) return; // 自己的回声
    if (rpcId == null &&
        _lastSentText == text &&
        _lastSentAt != null &&
        DateTime.now().difference(_lastSentAt!) < const Duration(seconds: 60)) {
      // 无 rpcId 的回声（如旧版本/插件写入），按文本+时间兜底去重
      _lastSentText = null;
      return;
    }
    _touchActivity();
    setState(() {
      _messages.add(DshMessage(
        id: key.isEmpty ? 'u-${_uuid.v4()}' : key,
        role: 'user',
        content: text,
      ));
    });
    _scrollToBottom();
  }

  // ---------- 变更 / 审批 / 问题 ----------

  void _onToolView(({
    String? callId, String card, String title,
    List<Map<String, String?>> diffs, bool done, int? turn,
  }) v) {
    if (!mounted) return;
    _touchActivity();
    setState(() {
      _changes.applyView(
        diffs: v.diffs, title: v.title, done: v.done, turn: v.turn);
    });
  }

  void _onApproval(({
    String rpcId, String sessionId, String approvalId,
    String toolName, String? reason,
  }) rec) {
    if (!mounted || rec.approvalId.isEmpty) return;
    if (_approvals.any((a) => a.approvalId == rec.approvalId)) return;
    setState(() {
      _approvals.add(PendingApproval(
        rpcId: rec.rpcId,
        sessionId: rec.sessionId,
        approvalId: rec.approvalId,
        toolName: rec.toolName,
        reason: rec.reason,
      ));
    });
    if (_settings.soundEnabled && _settings.approvalSound) {
      SoundService.approval(
          customPath: _settings.customSoundPath('approval'));
    }
  }

  void _onApprovalResolved(String approvalId) {
    if (!mounted) return;
    setState(() {
      _approvals.removeWhere((a) => a.approvalId == approvalId);
    });
  }

  Future<void> _answerApproval(PendingApproval a, bool allow) async {
    setState(() => a.answering = true);
    try {
      final ok = await _api!.answerApproval(
        rpcId: a.rpcId,
        sessionId: a.sessionId,
        approvalId: a.approvalId,
        allow: allow,
      );
      if (!mounted) return;
      if (ok) {
        // resolved 帧随后也会到，这里先行移除防重复点击
        setState(() {
          _approvals.removeWhere((x) => x.approvalId == a.approvalId);
        });
      } else {
        setState(() => a.answering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回答未被接受，可能已过期')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => a.answering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回答失败: $e')),
      );
    }
  }

  void _onQuestion(({
    String rpcId, String sessionId,
    List<Map<String, dynamic>> questions,
  }) rec) {
    if (!mounted || rec.rpcId.isEmpty || rec.questions.isEmpty) return;
    setState(() {
      _question = PendingQuestion(
        rpcId: rec.rpcId,
        sessionId: rec.sessionId,
        questions: rec.questions,
      );
    });
    if (_settings.soundEnabled && _settings.approvalSound) {
      SoundService.question(
          customPath: _settings.customSoundPath('question'));
    }
    _maybeShowQuestionDialog();
  }

  void _onQuestionResolved(String rpcId) {
    if (!mounted) return;
    if (_question?.rpcId == rpcId) {
      setState(() => _question = null);
      if (_questionDialogOpen) {
        _questionDialogOpen = false;
        Navigator.of(context).maybePop();
      }
    }
  }

  void _maybeShowQuestionDialog() {
    final q = _question;
    if (q == null || _questionDialogOpen || !mounted) return;
    if (q.sessionId != _settings.sessionId) {
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
    _questionDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuestionSheet(question: q, onSubmit: _submitQuestion),
    ).then((_) {
      _questionDialogOpen = false;
    });
  }

  Future<void> _submitQuestion(List<Map<String, dynamic>> answers) async {
    final q = _question;
    if (q == null) return;
    final ok = await _api!.answerQuestion(
      rpcId: q.rpcId,
      sessionId: q.sessionId,
      answers: answers,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _question = null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回答未被接受，可能已过期')),
      );
      throw Exception('not accepted');
    }
  }

  // ---------- 发送 ----------
  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || !_connected) return;
    final sessionId = _settings.sessionId;
    if (sessionId == null) return;

    _inputController.clear();
    setState(() {
      _sending = true;
      _agentRunning = true;
      _messages.add(DshMessage(id: 'u-${_uuid.v4()}', role: 'user', content: text));
    });
    _scrollToBottom(force: true);

    try {
      final rpcId = await _api!.sendPrompt(sessionId, text);
      _pendingEchoRpc.add(rpcId);
      _lastSentText = text;
      _lastSentAt = DateTime.now();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
      setState(() => _agentRunning = false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel() async {
    final sessionId = _settings.sessionId;
    if (sessionId == null) return;
    try {
      await _api!.cancelSession(sessionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消失败: $e')),
      );
    }
  }

  /// force=true：发送/切会话时必滚；平时用户上翻看历史时不抢滚
  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!force && pos.maxScrollExtent - pos.pixels > 200) return;
      _scrollController.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final sessionId = _settings.sessionId;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _buildStatusDot(),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_agentRunning)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止',
              onPressed: _cancel,
            ),
          Builder(
            builder: (drawerContext) => IconButton(
              icon: Badge(
                label: Text('${_changes.items.length}'),
                isLabelVisible: _changes.items.isNotEmpty,
                child: const Icon(Icons.difference_outlined),
              ),
              tooltip: '变更',
              onPressed: !_connected
                  ? null
                  : () =>
                      Scaffold.of(drawerContext).openEndDrawer(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重连',
            onPressed: _boot,
          ),
        ],
      ),
      drawer: _buildSessionDrawer(sessionId),
      endDrawer: ChangesDrawer(tracker: _changes),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_activeTool != null) ToolStatusBar(toolName: _activeTool!),
          ..._buildPendingCards(sessionId),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildSessionDrawer(String? activeId) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('会话',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (_loadingSessions)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '刷新',
                      onPressed: _refreshSessions,
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建会话'),
              onTap: () => _createNewSession(),
            ),
            const Divider(height: 1),
            Expanded(
              child: _sessions.isEmpty
                  ? const Center(child: Text('暂无会话'))
                  : ListView(
                      children: _buildSessionGroups(activeId),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 会话活跃时间（ms）；缺失按 0 处理沉底
  int _activityOf(Map<String, dynamic> s) =>
      (s['updatedAt'] as int?) ?? 0;

  /// 本地活跃刷新：收到当前会话的任何事件即把 updatedAt 置为现在，
  /// 与 PC 平铺模式一致实时重排（等 host 持久化会有延迟）
  void _touchActivity() {
    final id = _settings.sessionId;
    if (id == null) return;
    for (final s in _sessions) {
      if (s['sessionId'] == id) {
        s['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        break;
      }
    }
  }

  /// 侧栏会话分组：按工作区分组，组内一律按活跃时间倒序（与 PC 平铺模式一致）
  List<Widget> _buildSessionGroups(String? activeId) {
    final byId = <String, Map<String, dynamic>>{
      for (final s in _sessions) (s['sessionId'] as String? ?? ''): s,
    };
    final widgets = <Widget>[];
    final grouped = <String>{};

    for (final w in _workspaces) {
      final wsId = w['workspaceId'] as String? ?? '';
      final title = (w['title'] as String?)?.trim();
      final path = w['path'] as String? ?? '';
      final ids = (w['sessionIds'] as List<dynamic>? ?? []).whereType<String>();
      final visible = ids.where(
        (id) => byId.containsKey(id) && !_archivedIds.contains(id),
      ).toList()
        // 组内按活跃倒序（PC 平铺模式同款），不用工作区手动顺序
        ..sort((a, b) =>
            _activityOf(byId[b]!).compareTo(_activityOf(byId[a]!)));
      if (visible.isEmpty) continue;
      grouped.addAll(visible);
      final expanded = _settings.expandedWs.contains(wsId);
      widgets.add(
        ListTile(
          dense: true,
          leading: Icon(
            expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
            size: 20,
          ),
          title: Text(
            (title == null || title.isEmpty) ? path : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: (title != null && title.isNotEmpty)
              ? Text(path, maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: '在此工作区新建会话',
                onPressed: () => _createNewSession(workspaceId: wsId),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
            ],
          ),
          onTap: () {
            _settings.setWsExpanded(wsId, !expanded);
            setState(() {});
          },
        ),
      );
      if (!expanded) continue;
      for (final id in visible) {
        widgets.add(_sessionTile(byId[id]!, activeId, indented: true));
      }
    }

    // 未分组：不在任何工作区 account 里的会话，按活跃倒序
    final ungrouped = byId.keys.where(
      (id) => id.isNotEmpty && !grouped.contains(id) && !_archivedIds.contains(id),
    ).toList()
      ..sort((a, b) =>
          _activityOf(byId[b]!).compareTo(_activityOf(byId[a]!)));
    if (ungrouped.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
      final expanded = _settings.expandedWs.contains(_ungroupedKey);
      widgets.add(
        ListTile(
          dense: true,
          leading: const Icon(Icons.inbox_outlined, size: 20),
          title: const Text('未分组',
              style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
          ),
          onTap: () {
            _settings.setWsExpanded(_ungroupedKey, !expanded);
            setState(() {});
          },
        ),
      );
      if (expanded) {
        for (final id in ungrouped) {
          widgets.add(_sessionTile(byId[id]!, activeId, indented: true));
        }
      }
    }
    return widgets;
  }

  Widget _sessionTile(Map<String, dynamic> s, String? activeId,
      {bool indented = false}) {
    final id = s['sessionId'] as String? ?? '';
    final selected = id == activeId;
    final running = s['running'] == true;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(
        left: indented ? 32 : 16,
        right: 16,
      ),
      selected: selected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.4),
      leading: Icon(
        running
            ? Icons.sync
            : (s['blank'] == true
                ? Icons.chat_bubble_outline
                : Icons.chat_bubble),
        size: 20,
      ),
      title: Text(
        sessionTitleOf(s),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        timeAgoOf(s['updatedAt'] as int?),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      // 未读：控制台标出的后台完成会话在这里也露个点
      trailing: Consumer<SettingsService>(
        builder: (_, settings, __) =>
            settings.unviewedIds.contains(id)
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  )
                : const SizedBox.shrink(),
      ),
      onTap: () => _switchSession(id),
    );
  }

  /// 输入栏上方：本会话审批卡 + 问题回答入口（他会话的排后面，可跳转）
  List<Widget> _buildPendingCards(String? sessionId) {
    final cards = <Widget>[];
    final mine =
        _approvals.where((a) => a.sessionId == sessionId).toList();
    final foreign =
        _approvals.where((a) => a.sessionId != sessionId).toList();
    for (final a in [...mine, ...foreign]) {
      cards.add(ApprovalCard(
        approval: a,
        isForeignSession: a.sessionId != sessionId,
        onAnswer: (allow) => _answerApproval(a, allow),
        onViewSession: () => _switchSession(a.sessionId),
      ));
    }
    final q = _question;
    if (q != null && q.sessionId == sessionId && !_questionDialogOpen) {
      cards.add(
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: OutlinedButton.icon(
            onPressed: _maybeShowQuestionDialog,
            icon: const Icon(Icons.help_outline),
            label: Text('有 ${q.questions.length} 个问题待回答'),
          ),
        ),
      );
    }
    return cards;
  }

  Widget _buildStatusDot() {
    final color = !_connected
        ? Colors.red
        : _agentRunning
            ? Colors.orange
            : Colors.green;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildBody() {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在连接 DSH…'),
          ],
        ),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  _reconnectAttempts = 0;
                  _boot();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('开始和 Agent 对话吧', style: TextStyle(fontSize: 16)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) => MessageBubble(message: _messages[i]),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: _connected,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '输入消息…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: (_connected && !_sending) ? _send : null,
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}