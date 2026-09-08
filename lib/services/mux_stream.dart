import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'mux_history.dart';

export 'mux_history.dart';

/// DSH 原生 mux 订阅：ws://host:port/api/remote.mux（upgrade 带 Cookie）
///
/// 两条逻辑流：
/// · `$events` —— 审批 approval/request、提问 user-questions/request（waterfall）
///   应答走 POST /api/$events/result {args:{clientId,eventId,outcome}}
/// · session/follow —— 该会话 journal 事件 + assistant-stream 打字机帧
/// 外层帧形：{type:'item',streamId,value} | {type:'error'|'end',streamId}
class MuxStream {
  final String wsBaseUrl;

  /// "dsh-auth-xxx=value"，由启动令牌换取
  final String? cookie;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;
  String? _clientId;
  final _uuid = const Uuid();

  /// 当前会话 ID（follow 流只收该会话的事件）
  String? sessionId;

  /// 最近一次 snapshot 的日志游标（session/page 的 throughSeq 用）
  int? lastCursor;

  /// follow 开窗快照：records 元素形如 {type:'event', event:{type,seq,data}}
  void Function(List<Map<String, dynamic>> records)? onSnapshot;

  void Function(String delta)? onTextDelta;
  void Function(String text)? onAssistantMessage;
  void Function(String text, String? rpcId, String seq)? onUserMessage;
  void Function(
      ({
        String rpcId,
        String sessionId,
        String approvalId,
        String toolName,
        String? reason
      }))? onApproval;
  void Function(String approvalId)? onApprovalResolved;
  void Function(
      ({
        String rpcId,
        String sessionId,
        List<Map<String, dynamic>> questions
      }))? onQuestion;
  void Function(String rpcId)? onQuestionResolved;
  void Function(ToolViewRecord rec)? onToolView;
  void Function(String toolName)? onToolCall;
  void Function()? onToolResult;
  void Function()? onTurnEnd;
  void Function(List<Map<String, dynamic>> queueItems)? onQueueUpdate;
  void Function()? onDisconnected;
  void Function(String message)? onError;

  MuxStream({required this.wsBaseUrl, this.cookie});

  bool get isConnected => _channel != null;

  String get _httpBase => wsBaseUrl.startsWith('wss')
      ? 'https${wsBaseUrl.substring(3)}'
      : 'http${wsBaseUrl.substring(2)}';

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (cookie != null && cookie!.isNotEmpty) h['Cookie'] = cookie!;
    return h;
  }

  void connect() {
    if (_disposed) return;
    disconnect();
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$wsBaseUrl/api/remote.mux'),
        headers: _headers,
      );
      _send({
        'type': 'open',
        'streamId': 'evt',
        'endpoint': r'$events',
        'payload': {'args': {}},
      });
      if (sessionId != null && sessionId!.isNotEmpty) {
        _send({
          'type': 'open',
          'streamId': 'fol',
          'endpoint': 'session/follow',
          'payload': {
            'args': {
              'request': {
                'address': {'kind': 'session', 'sessionId': sessionId},
                'assistantStream': true,
                'maxMessages': 60,
              },
            },
          },
        });
      }
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
    } catch (e) {
      onError?.call('WebSocket 连接失败: $e');
      _handleDisconnect();
    }
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _clientId = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
  }

  void _handleDisconnect() {
    _channel = null;
    if (!_disposed) onDisconnected?.call();
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    late Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = frame['type'] as String? ?? '';
    if (type == 'item') {
      final value = frame['value'];
      if (value is Map<String, dynamic>) _onItem(value);
    } else if (type == 'error' || type == 'end') {
      _handleDisconnect();
    }
  }

  void _onItem(Map<String, dynamic> value) {
    switch (value['type'] as String? ?? '') {
      case 'ready':
        _clientId = value['clientId'] as String?;
        break;
      case 'waterfall':
        _onWaterfall(value);
        break;
      case 'cancel':
        // waterfall 已被别处应答/取消：按 eventId 清卡
        final id = value['eventId'] as String?;
        if (id != null && id.isNotEmpty) {
          onApprovalResolved?.call(id);
          onQuestionResolved?.call(id);
        }
        break;
      case 'snapshot':
        lastCursor = (value['cursor'] as num?)?.toInt();
        final records = (value['records'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        onSnapshot?.call(records);
        break;
      case 'event':
        _onJournalEvent(value['event']);
        break;
      case 'assistant-stream':
        _onAssistantFrame(value['frame']);
        break;
      default:
        break; // emit：api-session/* 忽略
    }
  }

  void _onWaterfall(Map<String, dynamic> value) {
    final event = value['event'] as String? ?? '';
    final eventId = value['eventId'] as String? ?? '';
    final request = value['request'];
    if (eventId.isEmpty || request is! Map<String, dynamic>) return;
    if (event == 'approval/request') {
      onApproval?.call((
        rpcId: eventId,
        sessionId: sessionId ?? '',
        approvalId: request['callId'] as String? ?? '',
        toolName: request['toolName'] as String? ?? 'tool',
        reason: request['reason'] as String?,
      ));
    } else if (event == 'user-questions/request') {
      final qs = (request['questions'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      onQuestion?.call((
        rpcId: eventId,
        sessionId: sessionId ?? '',
        questions: qs,
      ));
    }
  }

  void _onJournalEvent(dynamic eventDyn) {
    if (eventDyn is! Map<String, dynamic>) return;
    final type = eventDyn['type'] as String? ?? '';
    final data = eventDyn['data'];
    final rec = parseDiffView(
      viewSlot: eventDyn['view'],
      eventType: type,
      data: data,
      done: false,
    );
    if (rec != null) onToolView?.call(rec);
    if (data is! Map<String, dynamic>) {
      if (type == 'turn/end') onTurnEnd?.call();
      return;
    }
    _handleSessionEvent(type, eventDyn, data);
  }

  void _onAssistantFrame(dynamic frameDyn) {
    if (frameDyn is! Map<String, dynamic>) return;
    if (frameDyn['type'] != 'chunk') return;
    final chunk = frameDyn['chunk'];
    if (chunk is Map<String, dynamic> && chunk['type'] == 'text-delta') {
      final text = chunk['text'] as String? ?? '';
      if (text.isNotEmpty) onTextDelta?.call(text);
    }
  }

  Future<bool> _postEventResult(String eventId, Object value) async {
    final clientId = _clientId;
    if (clientId == null || eventId.isEmpty) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$_httpBase/api/\$events/result'),
            headers: _headers,
            body: jsonEncode({
              'type': 'client-request',
              'rpcId': _uuid.v4(),
              'method': r'$events/result',
              'payload': {
                'args': {
                  'clientId': clientId,
                  'eventId': eventId,
                  'outcome': {'kind': 'result', 'value': value},
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = data['result'];
      return result is Map && result['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 应答审批：'allowed-once' | 'rejected'
  Future<bool> respondApproval(String eventId, bool allow) =>
      _postEventResult(eventId, allow ? 'allowed-once' : 'rejected');

  /// 应答提问：{answers:[{id, selected:[label...], custom?}]}
  Future<bool> respondQuestion(
          String eventId, List<Map<String, dynamic>> answers) =>
      _postEventResult(eventId, {'answers': answers});

  void _handleSessionEvent(
      String type, Map<String, dynamic> event, Map<String, dynamic> data) {
    switch (type) {
      case 'user/message':
        final text = extractContentBlocks(data['content']);
        String? rpcId;
        final source = data['source'];
        if (source is Map<String, dynamic>) {
          rpcId = source['rpcId'] as String?;
        }
        final seq = '${event['seq'] ?? ''}';
        if (text.isNotEmpty) onUserMessage?.call(text, rpcId, seq);
        break;
      case 'assistant/chunk':
        final chunk = data['chunk'];
        if (chunk is Map<String, dynamic> && chunk['type'] == 'text-delta') {
          final text = chunk['text'] as String? ?? '';
          if (text.isNotEmpty) onTextDelta?.call(text);
        }
        break;
      case 'assistant/message':
        final text = extractAssistantText(data['message']);
        if (text.isNotEmpty) onAssistantMessage?.call(text);
        break;
      case 'tool/call':
        onToolCall?.call(data['name'] as String? ?? 'tool');
        break;
      case 'tool/result':
        onToolResult?.call();
        break;
      case 'turn/end':
        onTurnEnd?.call();
        break;
    }
  }
}
