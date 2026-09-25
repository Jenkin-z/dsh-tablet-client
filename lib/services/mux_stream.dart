import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/constants.dart';
import 'mux_history.dart';

export 'mux_history.dart';

part 'mux_session_handler.dart';

/// DSH 原生 mux 订阅：ws://host:port/api/remote.mux（upgrade 带 Cookie）
///
/// 四条逻辑流：
/// · `$events`          —— 审批 approval/request、提问 user-questions/request（waterfall）
///   应答走 POST /api/$events/result {args:{clientId,eventId,outcome}}
/// · session/follow     —— 该会话 journal 事件 + assistant-stream 打字机帧
/// · workspace/follow   —— 归档列表增量
/// · session/control    —— 全局控制流：queue/jobs/projection 实时推送
///
/// 外层帧形：{type:'item',streamId,value} | {type:'error'|'end',streamId}
///
/// 物理连接管理内置：断线后自动指数退避重连，重连后自动恢复所有逻辑流。
///
/// 重构后：所有事件都通过回调分发到 MuxEventDispatcher，不再自己维护业务状态。
class MuxStream {
  final String wsBaseUrl;
  final String? cookie;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;
  String? _clientId;
  final _uuid = const Uuid();
  String? sessionId;
  int? lastCursor;
  /// 开窗快照是否还有更早历史（配合 session/page 翻页）
  bool snapshotHasMore = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  int _revision = 0;

  /// 助手流 revision 与最近的 chunk 稠密序号（用于丢弃乱序/重复 chunk）
  int? _assistantRevision;
  int? _lastChunkIndex;

  // ── 事件回调（全部分发到 MuxEventDispatcher）────

  void Function(List<Map<String, dynamic>> records)? onSnapshot;
  /// 开窗快照的会话投影（标题、模型等实时元数据）
  void Function(Map<String, dynamic> projections)? onProjections;
  void Function(String delta)? onTextDelta;
  void Function(String text)? onAssistantMessage;

  /// `assistant/message` 定稿收尾（第二参为「是否被停止」）
  void Function(String text, bool interrupted)? onAssistantFinal;
  void Function(String text, String? rpcId, String seq)? onUserMessage;
  void Function({
    required String rpcId,
    required String sessionId,
    required String approvalId,
    required String toolName,
    String? reason,
  })? onApproval;
  void Function(String approvalId)? onApprovalResolved;
  void Function({
    required String rpcId,
    required String sessionId,
    required List<Map<String, dynamic>> questions,
  })? onQuestion;
  void Function(String rpcId)? onQuestionResolved;
  void Function(ToolViewRecord rec)? onToolView;
  void Function(String toolName, String? arguments)? onToolCall;
  void Function()? onToolResult;
  void Function()? onTurnStart;
  void Function()? onTurnEnd;
  void Function(List<Map<String, dynamic>> queueItems)? onQueueUpdate;

  /// `session/control` 的 jobs 帧（完整替换集）
  void Function(List<Map<String, dynamic>> jobs)? onJobsUpdate;
  void Function(List<String> archivedSessionIds)? onWorkspaceBaseline;
  void Function(String sessionId, bool running)? onSessionStatus;
  void Function(String sessionId, String message)? onSessionError;
  void Function(Map<String, dynamic> baseline)? onControlBaseline;
  void Function(String sessionId, String key, dynamic value)? onProjectionChange;
  void Function()? onReconnecting;
  void Function()? onReconnected;
  void Function()? onDisconnected;
  void Function(String message)? onError;

  /// `$events` 收到 `ready` 帧（真正可用于应答的时机）
  void Function()? onReady;

  MuxStream({required this.wsBaseUrl, this.cookie});

  bool get isConnected => _channel != null;
  int get clientId => _revision;

  String get _httpBase => wsBaseUrl.startsWith('wss')
      ? 'https${wsBaseUrl.substring(3)}'
      : 'http${wsBaseUrl.substring(2)}';

  Map<String, String> get _headers {
    final h = <String, String>{};
    if (cookie != null && cookie!.isNotEmpty) {
      h['Cookie'] = cookie!;
    }
    return h;
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('MuxStream send failed: $e');
    }
  }

  // ── 连接 ────────────────────────────────────────

  Future<void> connect() async {
    if (_disposed) return;
    _cancelReconnect();
    _revision++;

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$wsBaseUrl/api/remote.mux'),
        headers: _headers,
        pingInterval: const Duration(seconds: 20),
      );

      // 打开 $events 流
      _send({
        'type': 'open',
        'streamId': 'evt',
        'endpoint': r'$events',
        'payload': {'args': {}},
      });

      // 打开 session/follow 流
      //
      // Host 侧签名是 follow(request: SessionFollowRequest, signal)，
      // 生成客户端规则「单对象首参 → 线上字段名即参数名」，
      // 所以 args 里**必须有 request 包装层**：
      //   args: { request: { address, assistantStream, maxMessages } }
      // 缺了这层 Host 会因参数解析失败直接拒流（无历史、无流式）。
      if (sessionId != null && sessionId!.isNotEmpty) {
        _send({
          'type': 'open',
          'streamId': 'fol',
          'endpoint': 'session/follow',
          'payload': {
            'args': {
              'request': {
                'address': {
                  'kind': 'session',
                  'sessionId': sessionId,
                },
                'assistantStream': true,
                'maxMessages': 60,
              }
            }
          },
        });
      }

      // 打开 workspace/follow 流
      _send({
        'type': 'open',
        'streamId': 'wfo',
        'endpoint': 'workspace/follow',
        'payload': {'args': {}},
      });

      // 打开 session/control 流
      _send({
        'type': 'open',
        'streamId': 'ctl',
        'endpoint': 'session/control',
        'payload': {'args': {}},
      });

      _sub = _channel!.stream.listen(
        _onData,
        onDone: _onDone,
        onError: _onError,
        cancelOnError: false,
      );

      _reconnectAttempts = 0;
    } catch (e) {
      debugPrint('MuxStream connect failed: $e');
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _cancelReconnect();
    _closeChannel();
  }

  void dispose() {
    _disposed = true;
    disconnect();
  }

  void _closeChannel() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    // clientId 与物理 socket 绑定，连接一断立即作废
    _clientId = null;
  }

  // ── 重连（指数退避）────

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _closeChannel();
    onReconnecting?.call();

    _reconnectAttempts++;
    final delay = _reconnectAttempts <= reconnectFastLimit
        ? Duration(seconds: reconnectFastDelaySec)
        : Duration(
            seconds: min(
              reconnectSlowDelaySec * pow(2, _reconnectAttempts - reconnectFastLimit).toInt(),
              reconnectMaxDelaySec,
            ),
          );

    _reconnectTimer = Timer(delay, () {
      if (!_disposed) connect();
    });
  }

  void _onDone() {
    if (_disposed) return;
    _scheduleReconnect();
  }

  void _onError(Object error) {
    if (_disposed) return;
    debugPrint('MuxStream error: $error');
    onError?.call('$error');
    _scheduleReconnect();
  }

  // ── 帧分发 ──────────────────────────────────────

  void _onData(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MuxStream parse failed: $e');
      return;
    }

    final type = msg['type'] as String?;
    final streamId = msg['streamId'] as String?;

    if (type == 'item') {
      final value = msg['value'] as Map<String, dynamic>?;
      if (value == null) return;
      _handleItem(streamId ?? '', value);
    } else if (type == 'error') {
      final error = msg['error'] as Map<String, dynamic>?;
      debugPrint('MuxStream stream error [$streamId]: ${error?['message']}');
    } else if (type == 'end') {
      debugPrint('MuxStream stream ended [$streamId]');
    }
  }

  void _handleItem(String streamId, Map<String, dynamic> value) {
    switch (streamId) {
      case 'evt':
        _handleEvent(value);
        break;
      case 'fol':
        _handleFollow(value);
        break;
      case 'wfo':
        _handleWorkspaceFollow(value);
        break;
      case 'ctl':
        _handleControl(value);
        break;
    }
  }

  void _handleEvent(Map<String, dynamic> value) {
    switch (value['type'] as String? ?? '') {
      case 'ready':
        // clientId 与物理 socket 绑定，重连后由新的 ready 帧替换
        final cid = value['clientId'] as String?;
        if (cid != null && cid.isNotEmpty) {
          _clientId = cid;
        }
        // 已能应答审批/提问，视为真正连上
        onReady?.call();
        break;
      case 'waterfall':
        _handleWaterfall(value);
        break;
      case 'cancel':
        // waterfall 已被别处应答/取消：按 eventId 清卡
        final id = value['eventId'] as String?;
        if (id != null && id.isNotEmpty) {
          onApprovalResolved?.call(id);
          onQuestionResolved?.call(id);
        }
        break;
      case 'emit':
        // 会话运行状态/错误的唯一实时来源（api-session/*）
        _onEmit(value);
        break;
    }
  }

  /// `$events` waterfall：审批 / 提问请求
  ///
  /// 帧形（Host 侧 stream-protocol.ts RemoteEventInvocationFrame）：
  /// `{ type:'waterfall', event, eventId, agentId, request }`
  /// 其中 `agentId` 即会话 ID，用它才能正确区分「别的会话发来的审批」。
  void _handleWaterfall(Map<String, dynamic> value) {
    final event = value['event'] as String? ?? '';
    final eventId = value['eventId'] as String? ?? '';
    final request = value['request'];
    if (eventId.isEmpty || request is! Map<String, dynamic>) return;

    final sid = (value['agentId'] as String?) ?? sessionId ?? '';
    if (event == 'approval/request') {
      onApproval?.call(
        rpcId: eventId,
        sessionId: sid,
        // 应答走 $events/result 的 eventId，故 approvalId 即 eventId
        approvalId: eventId,
        toolName: request['toolName'] as String? ?? 'tool',
        reason: request['reason'] as String?,
      );
    } else if (event == 'user-questions/request') {
      final questions = (request['questions'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      onQuestion?.call(
        rpcId: eventId,
        sessionId: sid,
        questions: questions,
      );
    }
  }

  void _handleFollow(Map<String, dynamic> value) {
    switch (value['type'] as String? ?? '') {
      case 'snapshot':
        lastCursor = (value['cursor'] as num?)?.toInt();
        snapshotHasMore = value['hasMore'] == true;

        // 会话元数据投影：标题等实时信息来源于此
        final projections = value['projections'];
        if (projections is Map<String, dynamic>) {
          onProjections?.call(projections);
        }

        final records = (value['records'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        onSnapshot?.call(records);

        // 重连时正在进行的助手流基线：不消费会丢字
        final baseline = value['assistantStream'];
        if (baseline is Map<String, dynamic>) {
          _adoptAssistantBaseline(baseline);
        }
        break;
      case 'event':
        _onJournalEvent(value['event']);
        break;
      case 'assistant-stream':
        _onAssistantFrame(value['frame']);
        break;
    }
  }

  /// 采纳开窗的助手流基线：把已累积的片段补回界面，并重置 chunk 序号
  void _adoptAssistantBaseline(Map<String, dynamic> baseline) {
    _assistantRevision = (baseline['revision'] as num?)?.toInt();
    final attempt = baseline['activeAttempt'];
    if (attempt is! Map<String, dynamic>) {
      // 没有进行中的尝试 → 清空序号，避免用旧序号丢弃新 chunk
      _lastChunkIndex = null;
      return;
    }
    _lastChunkIndex = (attempt['nextIndex'] as num?)?.toInt();
    final stream = attempt['stream'];
    if (stream is List) {
      final text = StringBuffer();
      for (final item in stream) {
        if (item is Map<String, dynamic> && item['type'] == 'text-delta') {
          text.write(item['text'] as String? ?? '');
        }
      }
      if (text.isNotEmpty) onTextDelta?.call(text.toString());
    }
  }

  void _handleWorkspaceFollow(Map<String, dynamic> value) {
    List<String>? ids;
    switch (value['type'] as String? ?? '') {
      case 'baseline':
        // baseline: value.value.archivedSessionIds
        final inner = value['value'];
        if (inner is Map<String, dynamic>) {
          ids = (inner['archivedSessionIds'] as List?)
              ?.whereType<String>()
              .toList();
        }
        break;
      case 'archived':
        ids = (value['archivedSessionIds'] as List?)
            ?.whereType<String>()
            .toList();
        break;
    }
    if (ids != null) onWorkspaceBaseline?.call(ids);
  }

  void _handleControl(Map<String, dynamic> value) {
    // session/control 帧为扁平结构：{ type, ...字段 }
    // 帧名以 DSH 官方协议为准（见 docs/DSH_WEB_ANALYSIS.md 流 3）
    switch (value['type'] as String? ?? '') {
      case 'baseline':
        // { queues: {sessionId: [...]}, jobs: {...}, projections: {...} }
        final raw = value['value'];
        onControlBaseline?.call(raw is Map<String, dynamic> ? raw : value);
        break;
      case 'projection':
        final sessionId = value['sessionId'] as String?;
        final key = value['key'] as String?;
        if (sessionId != null && key != null) {
          onProjectionChange?.call(sessionId, key, value['value']);
        }
        break;
      case 'queue':
        final items = value['items'] as List<dynamic>? ?? [];
        onQueueUpdate?.call(items.whereType<Map<String, dynamic>>().toList());
        break;
      case 'jobs':
        // 后台作业集合（完整替换集，非增量）
        final jobs = value['jobs'] as List<dynamic>? ?? [];
        onJobsUpdate?.call(jobs.whereType<Map<String, dynamic>>().toList());
        break;
      // 注意：这里**没有** session/status 或 session/error。
      // 运行状态只走 $events 的 api-session/status emit 帧。
    }
  }

  /// journal 事件帧：`{ type:'event', event:{ type, seq, time, data } }`
  void _onJournalEvent(dynamic eventDyn) {
    if (eventDyn is! Map<String, dynamic>) return;
    final type = eventDyn['type'] as String? ?? '';
    final data = eventDyn['data'];

    // diff 只来自 tool/result.data.meta.diffs（线上没有 view 字段）
    final rec = parseDiffView(eventType: type, data: data);
    if (rec != null) onToolView?.call(rec);

    if (data is! Map<String, dynamic>) {
      if (type == 'turn/end') onTurnEnd?.call();
      return;
    }
    _handleSessionEvent(this, type, eventDyn, data);
  }

  /// 打字机帧：`{ type:'assistant-stream', frame }`
  ///
  /// frame.type 为 `start` / `chunk` / `end`。
  /// `chunk` 帧带稠密 `index`，用它可以丢弃乱序与重复的增量 —— 这是
  /// `assistant-stream` 与 journal `assistant/chunk` 双路喂入时唯一可靠的去重依据。
  void _onAssistantFrame(dynamic frameDyn) {
    if (frameDyn is! Map<String, dynamic>) return;

    switch (frameDyn['type'] as String? ?? '') {
      case 'start':
        _assistantRevision = (frameDyn['revision'] as num?)?.toInt();
        _lastChunkIndex = null;
        break;

      case 'chunk':
        final revision = (frameDyn['revision'] as num?)?.toInt();
        // revision 变化说明进入了新的一代，重置序号
        if (revision != null && _assistantRevision != null && revision != _assistantRevision) {
          _assistantRevision = revision;
          _lastChunkIndex = null;
        } else if (revision != null) {
          _assistantRevision = revision;
        }

        final index = (frameDyn['index'] as num?)?.toInt();
        if (index != null) {
          final last = _lastChunkIndex;
          // 只接受严格递增的序号（重复或倒序一律丢弃）
          if (last != null && index <= last) return;
          _lastChunkIndex = index;
        }

        final chunk = frameDyn['chunk'];
        if (chunk is Map<String, dynamic> && chunk['type'] == 'text-delta') {
          final text = chunk['text'] as String? ?? '';
          if (text.isNotEmpty) onTextDelta?.call(text);
        }
        break;

      case 'end':
        // 一次尝试结束：不在此处落最终消息，交给 journal 的
        // assistant/message 事件，避免同一段文本出现两条气泡。
        _lastChunkIndex = null;
        break;
    }
  }

  /// `$events` 的 `emit` 帧：`{ type:'emit', event, args }`
  ///
  /// ⚠️ `emit` **只存在于 `$events` 流**，`session/follow` 上没有这个帧。
  /// 之前把它挂在 follow 的分支里，导致运行状态推送全部丢弃。
  ///
  /// `api-session/*` 是 Host 允许广播的白名单事件，args 是 Cordis
  /// 监听器的位置参数：
  ///   api-session/status   → [sessionId, running]
  ///   api-session/error    → [sessionId, message]
  ///   api-session/activity → [sessionId, updatedAt]
  void _onEmit(Map<String, dynamic> value) {
    final event = value['event'] as String?;
    final args = value['args'];
    if (event == null || args is! List || args.isEmpty) return;
    final sid = args[0];
    if (sid is! String || sid.isEmpty) return;

    switch (event) {
      case 'api-session/status':
        if (args.length < 2) return;
        onSessionStatus?.call(sid, args[1] == true);
        break;
      case 'api-session/error':
        if (args.length < 2) return;
        final message = args[1];
        if (message is String && message.isNotEmpty) {
          onSessionError?.call(sid, message);
        }
        break;
    }
  }

  // ── 事件应答 ────────────────────────────────────

  /// `POST /api/$events/result`
  ///
  /// 信封与 Host 侧 client\rpc.ts 一致：
  /// 请求 `{type:'client-request', rpcId, method, payload:{args}}`
  /// 响应 `{type:'server-response', rpcId, result:{ok:true} | {ok:false,error}}`
  ///
  /// [rejected] 非空时 outcome 用 `{kind:'rejected', error}`，否则用
  /// `{kind:'result', value}`。
  Future<bool> _postEventResult(
    String eventId,
    dynamic value, {
    Map<String, dynamic>? rejected,
  }) async {
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty || eventId.isEmpty) return false;

    final outcome = rejected != null
        ? {'kind': 'rejected', 'error': rejected}
        : {
            'kind': 'result',
            'value': value,
          };

    final rpcId = _uuid.v4();
    try {
      final resp = await http
          .post(
            Uri.parse('$_httpBase/api/\$events/result'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': 'client-request',
              'rpcId': rpcId,
              'method': r'$events/result',
              'payload': {
                'args': {
                  'clientId': clientId,
                  'eventId': eventId,
                  'outcome': outcome,
                },
              },
            }),
          )
          .timeout(eventResultTimeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        debugPrint('\$events/result auth failed event=$eventId');
        return false;
      }
      if (resp.statusCode != 200) {
        debugPrint('\$events/result HTTP ${resp.statusCode} event=$eventId');
        return false;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) {
        debugPrint('\$events/result malformed body event=$eventId');
        return false;
      }
      if (data['rpcId'] != rpcId) {
        debugPrint('\$events/result rpcId mismatch event=$eventId');
        return false;
      }
      final result = data['result'];
      if (result is! Map) {
        debugPrint('\$events/result missing result event=$eventId');
        return false;
      }
      if (result['ok'] == true) return true;

      // 失败时把 Host 的错误信息带出来，便于定位
      final error = result['error'];
      final message = error is Map ? error['message'] : null;
      debugPrint('\$events/result rejected event=$eventId: ${message ?? resp.body}');
      return false;
    } catch (e) {
      debugPrint('\$events/result failed event=$eventId: $e');
      return false;
    }
  }

  Future<bool> respondApproval(String eventId, bool allow) =>
      _postEventResult(eventId, allow ? 'allowed-once' : 'rejected');

  Future<bool> respondQuestion(
          String eventId, List<Map<String, dynamic>> answers) =>
      _postEventResult(eventId, {'answers': answers});

  /// 放弃回答：Web 端 ✕ 的语义是 rejected + ASK_CANCELLED
  ///
  /// 不发这个，Host 侧的提问会一直挂着等（connection 断开前不会自动结束）。
  Future<bool> cancelQuestion(String eventId) => _postEventResult(
        eventId,
        null,
        rejected: {
          'name': 'UserQuestionError',
          'code': 'ASK_CANCELLED',
          'message': 'the user cancelled ask_user_question',
        },
      );
}