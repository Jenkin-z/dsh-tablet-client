import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// DSH mux 事件流订阅
///
/// 连 `ws://<host>:<port>/api/events.mux`，连上后什么都不发（发任何消息
/// 服务端都会以 1008 关闭——这是下行专用通道，上行走 HTTP）。
/// 收到的每帧都是 server-request：{ type, rpcId, method, payload }，
/// payload 为 MuxFrame，聊天只关心 type == 'session/event' 且 sessionId
/// 匹配当前会话的帧。
class MuxStream {
  final String wsBaseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;

  /// 当前会话 ID（只处理该会话的事件）
  String? sessionId;

  /// 流式文本增量（assistant/chunk 的 text-delta）
  void Function(String delta)? onTextDelta;

  /// assistant 最终消息（assistant/message 全文）
  void Function(String text)? onAssistantMessage;

  /// PC/其他端发来的用户消息（text, 发送方rpcId, 事件seq）
  /// rpcId 为自己刚发的可用于回声去重；seq 用于跨历史去重
  void Function(String text, String? rpcId, String seq)? onUserMessage;

  /// 审批请求：{ rpcId(回答时原样带回), sessionId, approvalId, toolName, reason }
  void Function(({String rpcId, String sessionId, String approvalId, String toolName, String? reason}))? onApproval;

  /// 审批已解决（任意端回答后）：approvalId
  void Function(String approvalId)? onApprovalResolved;

  /// 问题请求：{ rpcId(回答时原样带回), sessionId, questions(原样结构) }
  void Function(({String rpcId, String sessionId, List<Map<String, dynamic>> questions}))? onQuestion;

  /// 问题已解决：frame rpcId
  void Function(String rpcId)? onQuestionResolved;

  /// 工具视图（变更栏数据源）：diff 卡片解析结果
  /// done=false 来自 call（待执行），done=true 来自 result（已应用）
  void Function(({
    String? callId, String card, String title,
    List<Map<String, String?>> diffs, bool done, int? turn,
  }))? onToolView;

  /// 工具调用状态条（tool/call 工具名，轻量提示）
  void Function(String toolName)? onToolCall;

  /// 一轮结束（turn/end）
  void Function()? onTurnEnd;

  /// 连接断开
  void Function()? onDisconnected;

  /// 流错误
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

    // 审批 / 问题帧（非 session/event）
    if (ptype == 'approval/requested') {
      onApproval?.call((
        rpcId: frameRpcId ?? '',
        sessionId: payload['sessionId'] as String? ?? '',
        approvalId: payload['approvalId'] as String? ?? '',
        toolName: payload['toolName'] as String? ?? 'tool',
        reason: payload['reason'] as String?,
      ));
      return;
    }
    if (ptype == 'approval/resolved') {
      final id = payload['approvalId'] as String?;
      if (id != null) onApprovalResolved?.call(id);
      return;
    }
    if (ptype == 'question/requested') {
      final qs = (payload['questions'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      onQuestion?.call((
        rpcId: frameRpcId ?? '',
        sessionId: payload['sessionId'] as String? ?? '',
        questions: qs,
      ));
      return;
    }
    if (ptype == 'question/resolved') {
      if (frameRpcId != null) onQuestionResolved?.call(frameRpcId);
      return;
    }

    if (payload['type'] != 'session/event') return;
    if (sessionId != null && payload['sessionId'] != sessionId) return;

    final event = payload['event'];
    if (event is! Map<String, dynamic>) return;
    final type = event['type'] as String? ?? '';
    final data = event['data'];
    // 工具视图槽：变更栏数据源（call/result 帧都可能带）
    _emitToolView(payload['view'], type, data);
    if (data is! Map<String, dynamic>) {
      if (type == 'turn/end') onTurnEnd?.call();
      return;
    }

    switch (type) {
      case 'user/message': {
        final text = _extractContentBlocks(data['content']);
        String? rpcId;
        final source = data['source'];
        if (source is Map<String, dynamic>) {
          rpcId = source['rpcId'] as String?;
        }
        final seq = '${event['seq'] ?? ''}';
        if (text.isNotEmpty) onUserMessage?.call(text, rpcId, seq);
        break;
      }
      case 'assistant/chunk':
        final chunk = data['chunk'];
        if (chunk is Map<String, dynamic> &&
            chunk['type'] == 'text-delta') {
          final text = chunk['text'] as String? ?? '';
          if (text.isNotEmpty) onTextDelta?.call(text);
        }
        break;
      case 'assistant/message':
        final text = _extractAssistantText(data['message']);
        if (text.isNotEmpty) onAssistantMessage?.call(text);
        break;
      case 'tool/call':
        final name = data['name'] as String? ?? 'tool';
        onToolCall?.call(name);
        break;
      case 'turn/end':
        onTurnEnd?.call();
        break;
      default:
        break;
    }
  }

  /// 从 assistant/message 的 message 字段提取纯文本
  static String _extractAssistantText(dynamic message) {
    if (message is! Map<String, dynamic>) return '';
    final content = message['content'];
    if (content is! List) return '';
    final buf = StringBuffer();
    for (final part in content) {
      if (part is Map<String, dynamic> && part['type'] == 'text') {
        buf.write(part['text'] as String? ?? '');
      }
    }
    return buf.toString();
  }

  /// 解析 view 槽并发出 onToolView；只收 card == 'diff' 的文件变更
  void _emitToolView(dynamic viewSlot, String eventType, dynamic data) {
    if (viewSlot is! Map<String, dynamic>) return;
    final for_ = viewSlot['for'] as String?;
    final v = viewSlot['view'];
    if (v is! Map<String, dynamic> || v['card'] != 'diff') return;
    final rawDiffs = v['diffs'];
    if (rawDiffs is! List) return;
    final diffs = <Map<String, String?>>[];
    for (final d in rawDiffs) {
      if (d is! Map<String, dynamic>) continue;
      diffs.add({
        'path': d['path'] as String? ?? '',
        'oldText': d['oldText'] as String?,
        'newText': d['newText'] as String? ?? '',
      });
    }
    if (diffs.isEmpty) return;
    String? callId;
    int? turn;
    if (data is Map<String, dynamic>) {
      callId = data['callId'] as String?;
      turn = data['turn'] as int?;
    }
    onToolView?.call((
      callId: callId,
      card: 'diff',
      title: v['title'] as String? ?? eventType,
      diffs: diffs,
      done: for_ == 'result',
      turn: turn,
    ));
  }

  /// 从 history 条目（含 view 回填）提取 diff 视图记录
  static List<({
    String? callId, String card, String title,
    List<Map<String, String?>> diffs, bool done, int? turn,
  })> parseHistoryViews(List<dynamic> entries) {
    final out = <({
      String? callId, String card, String title,
      List<Map<String, String?>> diffs, bool done, int? turn,
    })>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final event = entry['event'];
      if (event is! Map<String, dynamic>) continue;
      final viewSlot = entry['view'];
      if (viewSlot is! Map<String, dynamic>) continue;
      final v = viewSlot['view'];
      if (v is! Map<String, dynamic> || v['card'] != 'diff') continue;
      final rawDiffs = v['diffs'];
      if (rawDiffs is! List) continue;
      final diffs = <Map<String, String?>>[];
      for (final d in rawDiffs) {
        if (d is! Map<String, dynamic>) continue;
        diffs.add({
          'path': d['path'] as String? ?? '',
          'oldText': d['oldText'] as String?,
          'newText': d['newText'] as String? ?? '',
        });
      }
      if (diffs.isEmpty) continue;
      final data = event['data'];
      String? callId;
      int? turn;
      if (data is Map<String, dynamic>) {
        callId = data['callId'] as String?;
        turn = data['turn'] as int?;
      }
      out.add((
        callId: callId,
        card: 'diff',
        title: v['title'] as String? ?? (event['type'] as String? ?? ''),
        diffs: diffs,
        // 历史里的一律视为已应用
        done: true,
        turn: turn,
      ));
    }
    return out;
  }
  /// entry: { event: { type, seq, time, data }, view? }
  static List<({String role, String text, String id})> parseHistory(
      List<dynamic> entries) {
    final out = <({String role, String text, String id})>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final event = entry['event'];
      if (event is! Map<String, dynamic>) continue;
      final type = event['type'] as String? ?? '';
      final seq = '${event['seq'] ?? ''}';
      final data = event['data'];
      if (data is! Map<String, dynamic>) continue;

      if (type == 'user/message') {
        final text = _extractContentBlocks(data['content']);
        if (text.isNotEmpty) out.add((role: 'user', text: text, id: 'u$seq'));
      } else if (type == 'assistant/message') {
        final text = _extractAssistantText(data['message']);
        if (text.isNotEmpty) {
          out.add((role: 'assistant', text: text, id: 'a$seq'));
        }
      }
    }
    return out;
  }

  static String _extractContentBlocks(dynamic content) {
    if (content is! List) return '';
    final buf = StringBuffer();
    for (final part in content) {
      if (part is Map<String, dynamic> && part['type'] == 'text') {
        buf.write(part['text'] as String? ?? '');
      }
    }
    return buf.toString();
  }
}