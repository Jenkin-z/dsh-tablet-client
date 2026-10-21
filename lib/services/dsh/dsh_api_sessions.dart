part of 'dsh_api.dart';

// 会话列表 / 创建 / 发送 / 历史分页（DshApi 的 part 文件）
//
// 方法用 `mixin X on _DshApiCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin DshApiSessions on _DshApiCore {
  Future<List<Map<String, dynamic>>> listSessions({Duration? timeout}) async {
    // Host 形参名是 `_request: SessionListRequest`（下划线只是表示"保留不用"），
    // 生成客户端规则是「线上字段名 = 形参名」，所以这里**必须**是 `_request`。
    // 传 `{}` 会让 Host 参数解析失败 → 列表永远为空。
    // 依据：apps/web/tests/smoke-real.e2e.ts:755-766 的真实调用。
    final value = await rpc(
      'session/list',
      {'_request': <String, dynamic>{}},
      timeout: timeout,
    );
    final items = value['items'] as List<dynamic>? ?? [];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  /// 读取最近历史，用于完成通知摘要。
  ///
  /// 历史跟随仍以 mux 的 `session/follow` 为准；这里只做一次有上限的
  /// 快照读取，避免为了通知正文把整段历史拉下来。
  Future<Map<String, dynamic>> getHistory(
    String sessionId, {
    int? throughSeq,
    int? beforeSeq,
    int? maxMessages,
    Duration? timeout,
  }) async {
    final request = <String, dynamic>{
      'address': {'kind': 'session', 'sessionId': sessionId},
      'throughSeq': throughSeq ?? -1,
      if (beforeSeq != null) 'beforeSeq': beforeSeq,
      if (maxMessages != null) 'maxMessages': maxMessages,
    };
    final value = await rpc(
      'session/page',
      {'request': request},
      timeout: timeout,
    );
    return {
      'events': value['records'] ?? [],
      'hasMore': value['hasMore'] == true,
    };
  }

  Future<String> createSession(
      {String? cwd, String? agentPreset, String? workspaceId}) async {
    final request = <String, dynamic>{};
    if (cwd != null) request['cwd'] = cwd;
    if (agentPreset != null) request['agentPreset'] = agentPreset;
    if (workspaceId != null) request['workspaceId'] = workspaceId;
    final value = await rpc('session/create', {'request': request});
    return value['sessionId'] as String;
  }

  /// 发送提示；返回用于对账的 requestId
  ///
  /// [requestId] 由调用方预先给出，这样本地乐观气泡与 durable 消息
  /// 用的是同一个 id，回显才能精确对账（而不是靠内容去重）。
  Future<String> sendPrompt(String sessionId, String text,
      {String? requestId}) async {
    final rid = requestId ?? _uuid.v4();
    await rpc('session/prompt', {
      'request': {
        'requestId': rid,
        'sessionId': sessionId,
        'mode': 'queue',
        'content': [
          {'type': 'text', 'text': text}
        ],
      },
    });
    return rid;
  }

  Future<bool> testConnection() async {
    try {
      await listSessions();
      return true;
    } on DshAuthException {
      rethrow;
    } catch (_) {
      return false;
    }
  }
}
