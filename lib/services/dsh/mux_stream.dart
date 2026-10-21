import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../utils/constants.dart';
import 'mux_history.dart';

export 'mux_history.dart';

part 'mux_session_handler.dart';
part 'mux_connection.dart';
part 'mux_frame_events.dart';
part 'mux_frame_follow.dart';
part 'mux_event_result.dart';

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
/// 重构后：所有事件都通过回调分发到 EventDispatcher，不再自己维护业务状态。
///
/// 按职责拆分（私有 extension part 文件，同库共享私有作用域，对外 API 不变）：
/// - mux_connection.dart：连接生命周期 + 指数退避重连
/// - mux_frame_events.dart：外层帧分发 + $events + session/control
/// - mux_frame_follow.dart：session/follow + workspace/follow + assistant-stream
/// - mux_event_result.dart：HTTP 事件应答（$events/result）
/// - mux_session_handler.dart：journal 事件 → 回调映射
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

  // ── 事件回调（全部分发到 EventDispatcher）────

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

  Future<void> connect() => _connectImpl();

  void disconnect() {
    _cancelReconnect();
    _closeChannel();
  }

  void dispose() {
    _disposed = true;
    disconnect();
  }

  // ── 事件应答 ────────────────────────────────────

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
