part of 'mux_stream.dart';

// 外层帧分发 + $events 流 + session/control 流（MuxStream 的 part 文件）

extension on MuxStream {
  void _onData(dynamic data) {
    // 收到首帧业务数据 = 连接真正活了，重连计数才归零。
    // （HTTP/WS 握手成功不算稳定，见 ReconnectBackoff 注释）
    if (_backoff.attempts != 0) _backoff.markStable();
    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MuxStream parse failed: $e');
      // 非 JSON 帧：至少让用户知道连接数据出了问题（断线横幅/状态点可见）
      onError?.call('收到无法解析的数据帧');
      return;
    }

    final type = msg['type'] as String?;
    final streamId = msg['streamId'] as String?;

    if (type == 'item') {
      final value = msg['value'] as Map<String, dynamic>?;
      if (value == null) return;
      _handleItem(streamId ?? '', value);
    } else if (type == 'error') {
      _handleStreamError(streamId, msg['error']);
    } else if (type == 'end') {
      debugPrint('MuxStream stream ended [$streamId]');
    }
  }

  /// 外层 error 帧（RemoteStreamFailure：`{code, message, details}`）
  ///
  /// 之前只 debugPrint，用户侧毫无感知。session/follow（fol）的失败是
  /// 会话级错误（历史/打字机流断了，如 revision 跳号），走 onSessionError
  /// 上屏成 system 气泡；其余流（$events/control/workspace）没有会话位置，
  /// 交给 onError → setConnectionError（断线横幅 / 状态点 tooltip 可见）。
  void _handleStreamError(String? streamId, dynamic error) {
    final message = _describeStreamFailure(error);
    debugPrint('MuxStream stream error [$streamId]: $message');
    final sid = sessionId;
    if (streamId == 'fol' && sid != null && sid.isNotEmpty) {
      onSessionError?.call(sid, message);
      return;
    }
    onError?.call('[$streamId] $message');
  }

  String _describeStreamFailure(dynamic error) {
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
      final code = error['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return '数据流错误';
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
        // { type, sessionId, items } —— sessionId 必须带上，
        // 队列视图按会话隔离，别的会话的队列不能错记到当前会话头上
        final sid = value['sessionId'];
        final items = value['items'] as List<dynamic>? ?? [];
        if (sid is String && sid.isNotEmpty) {
          onQueueUpdate?.call(
            sid,
            items.whereType<Map<String, dynamic>>().toList(),
          );
        }
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
}
