part of 'dsh_api.dart';

// 搜索 / 重命名 / 队列管理（DshApi 的 part 文件）
//
// 对齐 DSH 官方 Web 端的会话管理接口。
//
// 方法用 `mixin X on _DshApiCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin DshApiExtras on _DshApiCore {
  /// 会话搜索（全文检索历史消息内容）
  ///
  /// 返回 `{ items: [{ sessionId, snippet }], hasMore: bool }`
  Future<Map<String, dynamic>> searchSessions(String query) async {
    // 端点是 session/search，不是 session/list
    final value = await rpc('session/search', {
      'request': {'query': query},
    });
    return {
      'items': value['items'] ?? [],
      'hasMore': value['hasMore'] == true,
    };
  }

  /// 重命名会话
  ///
  /// 返回 `{ title: String, seq: int }`
  Future<Map<String, dynamic>> renameSession(
      String sessionId, String title) async {
    final value = await rpc('session/rename', {
      'request': {'sessionId': sessionId, 'title': title},
    });
    return {'title': value['title'], 'seq': value['seq']};
  }

  /// 队列管理：编辑/删除/转插话待处理消息
  ///
  /// 信封依据：DSH_REMOTE_STREAM_MUX_PROTOCOL.md L2075
  /// `{ request: { sessionId, itemId, action } }` → `{ accepted: true }`。
  /// action 是按 kind 判别的联合：
  /// `{ kind: 'edit', content: [...] }` | `{ kind: 'remove' }` | `{ kind: 'steer' }`
  /// （edit/remove 形状见本文件历史注释；steer 依据 docs/DSH_WEB_ANALYSIS.md:43
  /// 「action: edit|remove|steer」，同族判别式形状类推为 `{ kind: 'steer' }`）
  Future<bool> updateQueue(
    String sessionId,
    String itemId,
    Map<String, dynamic> action,
  ) async {
    final value = await rpc('session/updateQueue', {
      'request': {
        'sessionId': sessionId,
        'itemId': itemId,
        'action': action,
      },
    });
    return value['accepted'] == true;
  }

  /// 把排队条目提前为插话（注入当前轮）
  Future<bool> steerQueuedItem(String sessionId, String itemId) =>
      updateQueue(sessionId, itemId, const {'kind': 'steer'});

  /// 删除排队条目
  Future<bool> removeQueuedItem(String sessionId, String itemId) =>
      updateQueue(sessionId, itemId, const {'kind': 'remove'});

  /// 编辑排队条目内容（content 按协议 PromptContentPart 数组下线）
  Future<bool> editQueuedItem(
      String sessionId, String itemId, String content) {
    return updateQueue(sessionId, itemId, {
      'kind': 'edit',
      'content': [
        {'type': 'text', 'text': content},
      ],
    });
  }
}
