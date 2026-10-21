part of 'dsh_api.dart';

// 取消会话 + 连通性探测（DshApi 的 part 文件）
//
// cancel 走独立的 HTTP 请求而不是 rpc()：它的超时更短、且诊断需要
// 原始响应文本，所以这里保留一份手写的信封。
//
// 方法用 `mixin X on _DshApiCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin DshApiCancel on _DshApiCore {
  Future<bool> cancelSession(String sessionId) async {
    final resp = await http
        .post(
          Uri.parse('$_rpcPrefix/session/cancel'),
          headers: _headers,
          body: jsonEncode({
            'type': 'client-request',
            'rpcId': _uuid.v4(),
            'method': 'session/cancel',
            'payload': {
              'args': {
                'request': {'sessionId': sessionId}
              }
            },
          }),
        )
        .timeout(cancelTimeout);
    _throwIfAuthFailed(resp);
    if (resp.statusCode != 200) {
      throw DshRpcException(
        code: 'http/${resp.statusCode}',
        message: 'HTTP ${resp.statusCode}: ${resp.body}',
        httpStatus: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    if (result['ok'] != true) {
      final error = result['error'] as Map<String, dynamic>;
      throw DshRpcException(
        code: error['code'] as String? ?? 'unknown',
        message: error['message'] as String? ?? '未知错误',
      );
    }
    final value =
        (result['value'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    return value['accepted'] == true;
  }

  /// 诊断用：返回 cancel 的原始响应文本（截断）。
  Future<String> cancelSessionRaw(String sessionId) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_rpcPrefix/session/cancel'),
            headers: _headers,
            body: jsonEncode({
              'type': 'client-request',
              'rpcId': _uuid.v4(),
              'method': 'session/cancel',
              'payload': {
                'args': {
                  'request': {'sessionId': sessionId}
                }
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      return 'HTTP ${resp.statusCode} ${resp.body}';
    } catch (e) {
      return 'ERR $e';
    }
  }
}
