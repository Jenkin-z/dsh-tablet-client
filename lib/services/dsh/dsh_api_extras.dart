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

  /// 队列管理：编辑/删除待处理消息
  ///
  /// action: { kind: 'edit', content: [...] } | { kind: 'remove' }
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
}
