part of 'mux_stream.dart';

// 事件应答：POST /api/$events/result（MuxStream 的 part 文件）

extension on MuxStream {
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
}
