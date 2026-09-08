import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/changes_tracker.dart';
import '../services/dsh_api.dart';
import '../services/dsh_auth.dart';
import '../services/mux_stream.dart';
import '../services/server_manager.dart';
import '../services/session_router.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../utils/session_format.dart';
import '../widgets/approval_card.dart';
import '../widgets/changes_drawer.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/question_sheet.dart';
import '../widgets/session_drawer.dart';
import '../widgets/tool_status_bar.dart';

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
  final Set<String> _pendingEchoRpc = {};
  final Set<String> _seenUserSeq = {};
  String? _lastSentText;
  DateTime? _lastSentAt;
  final ChangesTracker _changes = ChangesTracker();
  final List<PendingApproval> _approvals = [];
  final Set<String> _queuedTexts = {};  // 当前 session/queue 快照中的消息文本
  PendingQuestion? _question;
  bool _questionDialogOpen = false;
  SessionRouter? _router;
  ServerManager? _manager;
  bool _wasCurrentRunning = false;
  Timer? _approvalPollTimer;
  String _deltaBuffer = '';
  Timer? _deltaFlushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
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

  /// PC 端中断/取消时 mux 可能丢 turn/end；用 session.list 的 running 跃迁清工具条
  void _onMonitorTick() {
    if (!mounted) return;
    final srv = _settings.active;
    final id = _settings.sessionId;
    if (srv == null || id == null) return;
    Map<String, dynamic>? current;
    for (final s in _manager?.monitorOf(srv.id)?.sessions ?? const []) {
      if (s['sessionId'] == id) {
        current = s;
        break;
      }
    }
    final running = current?['running'] == true;
    if (_wasCurrentRunning && !running) {
      setState(() {
        _agentRunning = false;
        _activeTool = null;
        final idx = _messages.indexWhere((m) => m.isStreaming);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(isStreaming: false);
        }
      });
    }
    _wasCurrentRunning = running;
  }

  void _onRouteRequest() {
    final router = _router;
    if (router == null || !mounted) return;
    final target = router.sessionId;
    final serverId = router.serverId;
    if (target == null || serverId == null) return;
    if (serverId != _settings.activeServerId) return;
    if (target == _settings.sessionId && _connected) {
      router.consume(router.token);
      return;
    }
    if (!router.consume(router.token)) return;
    _switchSession(target);
  }

  @override
  void dispose() {
    _router?.removeListener(_onRouteRequest);
    _manager?.removeListener(_onMonitorTick);
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

  Future<void> _boot() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final srv = _settings.active;
    if (srv == null) {
      setState(() {
        _connecting = false;
        _connected = false;
        _error = '还没有 PC，去设置里添加。';
      });
      return;
    }
    if (srv.unpaired) {
      setState(() {
        _connecting = false;
        _connected = false;
        _error = '「${srv.name}」授权已过期，去设置里重新授权。';
      });
      return;
    }
    _api = DshApi(baseUrl: srv.httpUrl, cookie: srv.cookie);

    try {
      final ok = await _api!.testConnection();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _connecting = false;
          _connected = false;
          _error = '连接失败: ${srv.httpUrl}\n请检查 PC 端 DSH 是否启动、同一局域网。';
        });
        _scheduleReconnect();
        return;
      }
    } on DshAuthException catch (e) {
      if (!mounted) return;
      if (e.unpaired) {
        await _settings.patchServer(
          srv.id,
          (s) => s.copyWith(unpaired: true, lastError: e.message),
        );
      }
      setState(() {
        _connecting = false;
        _connected = false;
        _error = e.message;
      });
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
      await _settings.markSeen(_settings.seenKey(srv.id, sessionId));
      await _refreshSessions();
      _connectMux(sessionId);
      setState(() {
        _connecting = false;
        _connected = true;
        _error = null;
      });
      _reconnectAttempts = 0;
      _jumpToLatest();
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
      if (!mounted) return;
      setState(() {
        _sessions = items;
        _currentTitle = _titleFor(_settings.sessionId);
      });
    } catch (_) {
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


  /// mux follow 开窗快照 → 重建消息列表（历史）
  void _onMuxSnapshot(List<Map<String, dynamic>> records) {
    if (!mounted) return;
    final parsed = parseHistory(records);
    setState(() {
      _messages.clear();
      _seenUserSeq.clear();
      for (final p in parsed) {
        _messages.add(DshMessage(id: p.id, role: p.role, content: p.text));
        _seenUserSeq.add(p.id);
      }
      _changes.clear();
      for (final v in parseHistoryViews(records)) {
        _changes.applyView(
            diffs: v.diffs, title: v.title, done: v.done, turn: v.turn);
      }
    });
    _jumpToLatest();
  }

  Future<void> _switchSession(String sessionId) async {
    if (sessionId == _settings.sessionId && _connected) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).maybePop();
    await _settings.setSessionId(sessionId);
    final srv = _settings.active;
    if (srv != null) {
      await _settings.markSeen(_settings.seenKey(srv.id, sessionId));
    }
    setState(() {
      _messages.clear();
      _activeTool = null;
      _agentRunning = false;
      _currentTitle = _titleFor(sessionId);
      _pendingEchoRpc.clear();
      _queuedTexts.clear();
      _lastSentText = null;
      _lastSentAt = null;
      _changes.clear();
    });
    _connectMux(sessionId);
    _maybeShowQuestionDialog();
  }

  Future<void> _createNewSession() async {
    Navigator.of(context).maybePop();
    if (_api == null || !_connected) return;
    try {
      final id = await _api!.createSession();
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
    final mux = MuxStream(
      wsBaseUrl: _settings.wsUrl,
      cookie: _settings.active?.cookie,
    );
    mux.sessionId = sessionId;
    mux.onTextDelta = _onDelta;
    mux.onAssistantMessage = _onAssistantFinal;
    mux.onUserMessage = _onUserMessage;
    mux.onToolView = _onToolView;
    mux.onSnapshot = _onMuxSnapshot;
    mux.onApproval = _onApproval;
    mux.onApprovalResolved = _onApprovalResolved;
    mux.onQuestion = _onQuestion;
    mux.onQuestionResolved = _onQuestionResolved;
    mux.onToolCall = (name) {
      if (mounted) setState(() => _activeTool = name);
    };
    mux.onToolResult = _clearToolStatus;
    mux.onTurnEnd = _onTurnEnd;
    mux.onQueueUpdate = _onQueueUpdate;
    mux.onDisconnected = () {
      if (!mounted) return;
      setState(() => _connected = false);
      _scheduleReconnect();
    };
    mux.connect();
    setState(() => _connected = true);
    _mux = mux;
    _approvalPollTimer?.cancel();
    _approvalPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkApprovalsStale();
    });
  }

  void _clearToolStatus() {
    if (!mounted) return;
    if (_activeTool == null) return;
    setState(() => _activeTool = null);
  }

  void _onTurnEnd() {
    if (!mounted) return;
    setState(() {
      _agentRunning = false;
      _activeTool = null;
      _approvals.clear();
      _question = null;
      if (_questionDialogOpen) {
        _questionDialogOpen = false;
        Navigator.of(context).maybePop();
      }
    });
    final idx = _messages.indexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      setState(
          () => _messages[idx] = _messages[idx].copyWith(isStreaming: false));
    }
    if (_settings.soundEnabled && _settings.completionSound) {
      SoundService.done(customPath: _settings.customSoundPath('done'));
    }
    _refreshSessions();
  }

  /// session/queue 快照：对比队列和已显示的气泡，移除被 PC 端删掉的消息
  void _onQueueUpdate(List<Map<String, dynamic>> items) {
    if (!mounted) return;
    // 提取队列中每条消息的文本
    final currentQueued = <String>{};
    for (final item in items) {
      final msg = item['message'] as Map<String, dynamic>?;
      if (msg == null) continue;
      final content = msg['content'] as List<dynamic>? ?? [];
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map<String, dynamic> && part['type'] == 'text') {
          buf.write(part['text'] as String? ?? '');
        }
      }
      if (buf.isNotEmpty) currentQueued.add(buf.toString());
    }
    // 被删掉的：之前在队列里，现在不在了
    final removed = _queuedTexts.difference(currentQueued);
    _queuedTexts
      ..clear()
      ..addAll(currentQueued);
    if (removed.isEmpty) return;
    setState(() {
      _messages.removeWhere(
          (m) => m.role == 'user' && removed.contains(m.content));
    });
  }

  void _checkApprovalsStale() {
    if (!mounted || !_connected || _api == null) return;
    final sid = _settings.sessionId;
    if (sid == null) return;
    if (_approvals.isEmpty && _question == null) return;
    final cursor = _mux?.lastCursor;
    if (cursor == null) return;
    _api!.getHistory(sid, throughSeq: cursor, maxMessages: 10).then((result) {
      if (!mounted) return;
      final events = result['events'] as List<dynamic>? ?? [];
      for (final e in events) {
        final ev = e as Map<String, dynamic>? ?? {};
        final event = ev['event'] as Map<String, dynamic>?;
        final type = event?['type'] as String? ?? '';
        if (type == 'turn/start' || type == 'assistant/message') {
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
    final delay =
        Duration(seconds: _reconnectAttempts > 5 ? 30 : _reconnectAttempts * 3);
    _reconnectTimer = Timer(delay, () {
      if (mounted) _boot();
    });
  }

  void _onDelta(String delta) {
    if (!mounted) return;
    _touchActivity();
    _deltaBuffer += delta;
    _deltaFlushTimer ??= Timer(const Duration(milliseconds: 120), _flushDelta);
  }

  void _flushDelta() {
    _deltaFlushTimer = null;
    if (!mounted) return;
    final text = _deltaBuffer;
    _deltaBuffer = '';
    if (text.isEmpty) return;
    final idx = _messages.indexWhere((m) => m.isStreaming);
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
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    _deltaBuffer = '';
    setState(() {
      _activeTool = null;
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

  void _onUserMessage(String text, String? rpcId, String seq) {
    if (!mounted) return;
    final key = 'u$seq';
    if (seq.isNotEmpty && !_seenUserSeq.add(key)) return;
    if (rpcId != null && _pendingEchoRpc.remove(rpcId)) return;
    if (rpcId == null &&
        _lastSentText == text &&
        _lastSentAt != null &&
        DateTime.now().difference(_lastSentAt!) < const Duration(seconds: 60)) {
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

  void _onToolView(ToolViewRecord v) {
    if (!mounted) return;
    _touchActivity();
    setState(() {
      _changes.applyView(
          diffs: v.diffs, title: v.title, done: v.done, turn: v.turn);
    });
  }

  void _onApproval(
      ({
        String rpcId,
        String sessionId,
        String approvalId,
        String toolName,
        String? reason,
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
      SoundService.approval(customPath: _settings.customSoundPath('approval'));
    }
  }

  void _onApprovalResolved(String approvalId) {
    if (!mounted) return;
    // approvalId=callId；$events cancel 帧携带的是 waterfall eventId(=rpcId)
    setState(() {
      _approvals.removeWhere(
          (a) => a.approvalId == approvalId || a.rpcId == approvalId);
    });
  }

  Future<void> _answerApproval(PendingApproval a, bool allow) async {
    setState(() => a.answering = true);
    try {
      final ok = await (_mux?.respondApproval(a.rpcId, allow) ??
          Future.value(false));
      if (!mounted) return;
      if (ok) {
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

  void _onQuestion(
      ({
        String rpcId,
        String sessionId,
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
      SoundService.question(customPath: _settings.customSoundPath('question'));
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
    final ok = await (_mux?.respondQuestion(q.rpcId, answers) ??
        Future.value(false));
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

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || !_connected) return;
    final sessionId = _settings.sessionId;
    if (sessionId == null) return;

    _inputController.clear();
    setState(() {
      _sending = true;
      _agentRunning = true;
      _messages
          .add(DshMessage(id: 'u-${_uuid.v4()}', role: 'user', content: text));
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
    } finally {
      if (!mounted) return;
      setState(() {
        _agentRunning = false;
        _activeTool = null;
        final idx = _messages.indexWhere((m) => m.isStreaming);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(isStreaming: false);
        }
      });
    }
  }

  /// reverse ListView：pixels == 0 就是最新消息。
  /// 进会话时 ListView 可能还没挂上，Markdown 也会晚一帧撑高，所以连跳几帧。
  void _jumpToLatest([int left = 8]) {
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
      // reverse：离最新超过 200px 视为在看历史，不抢滚
      if (!force && pos.pixels > 200) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

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
                _settings.active == null
                    ? _currentTitle
                    : '${_settings.active!.name} · $_currentTitle',
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
                  : () => Scaffold.of(drawerContext).openEndDrawer(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重连',
            onPressed: _boot,
          ),
        ],
      ),
      drawer: SessionDrawer(
        sessions: _sessions,
        serverId: _settings.active?.id ?? '',
        activeId: sessionId,
        loading: _loadingSessions,
        onRefresh: _refreshSessions,
        onCreateUngrouped: () => _createNewSession(),
        onSelectSession: _switchSession,
      ),
      endDrawer: ChangesDrawer(tracker: _changes),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_activeTool != null) ToolStatusBar(toolName: _activeTool!),
          ..._buildPendingCards(sessionId),
          ChatInputBar(
            controller: _inputController,
            connected: _connected,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPendingCards(String? sessionId) {
    final cards = <Widget>[];
    final mine = _approvals.where((a) => a.sessionId == sessionId).toList();
    final foreign = _approvals.where((a) => a.sessionId != sessionId).toList();
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
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) =>
          MessageBubble(message: _messages[_messages.length - 1 - i]),
    );
  }
}
