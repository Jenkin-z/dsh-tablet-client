import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'mux_history.dart';

export 'mux_history.dart';

/// DSH mux 事件流订阅
///
/// 连 `ws://<host>:<port>/api/events.mux`，连上后什么都不发（发任何消息
/// 服务端都会以 1008 关闭——这是下行专用通道，上行走 HTTP）。
class MuxStream {
  final String wsBaseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;

  /// 当前会话 ID（只处理该会话的事件）
  String? sessionId;

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
  void Function()? onDisconnected;
  void Function(String message)? onError;

  MuxStream({required this.wsBaseUrl});

  bool get isConnected => _channel != null;

  void connect() {
    if (_disposed) return;
    disconnect();
    try {
      final url = Uri.parse('$wsBaseUrl/api/events.mux');
      _channel = WebSocketChannel.connect(url);
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

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
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
    final payload = frame['payload'];
    if (payload is! Map<String, dynamic>) return;
    final frameRpcId = frame['rpcId'] as String?;
    final ptype = payload['type'] as String? ?? '';

    if (_handleControl(ptype, payload, frameRpcId)) return;

    if (payload['type'] != 'session/event') return;
    if (sessionId != null && payload['sessionId'] != sessionId) return;

    final event = payload['event'];
    if (event is! Map<String, dynamic>) return;
    final type = event['type'] as String? ?? '';
    final data = event['data'];
    final rec = parseDiffView(
      viewSlot: payload['view'],
      eventType: type,
      data: data,
      done: payload['view'] is Map &&
          (payload['view'] as Map)['for'] == 'result',
    );
    if (rec != null) onToolView?.call(rec);
    if (data is! Map<String, dynamic>) {
      if (type == 'turn/end') onTurnEnd?.call();
      return;
    }
    _handleSessionEvent(type, event, data);
  }

  bool _handleControl(
      String ptype, Map<String, dynamic> payload, String? frameRpcId) {
    switch (ptype) {
      case 'approval/requested':
        onApproval?.call((
          rpcId: frameRpcId ?? '',
          sessionId: payload['sessionId'] as String? ?? '',
          approvalId: payload['approvalId'] as String? ?? '',
          toolName: payload['toolName'] as String? ?? 'tool',
          reason: payload['reason'] as String?,
        ));
        return true;
      case 'approval/resolved':
        final id = payload['approvalId'] as String?;
        if (id != null) onApprovalResolved?.call(id);
        return true;
      case 'question/requested':
        final qs = (payload['questions'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        onQuestion?.call((
          rpcId: frameRpcId ?? '',
          sessionId: payload['sessionId'] as String? ?? '',
          questions: qs,
        ));
        return true;
      case 'question/resolved':
        if (frameRpcId != null) onQuestionResolved?.call(frameRpcId);
        return true;
      default:
        return false;
    }
  }

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
