part of 'mux_stream.dart';

// 连接生命周期 + 指数退避重连（MuxStream 的 part 文件，必须保持私有）

extension on MuxStream {
  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('MuxStream send failed: $e');
    }
  }

  // ── 连接 ────────────────────────────────────────

  Future<void> _connectImpl() async {
    if (_disposed) return;
    _cancelReconnect();
    _revision++;

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$wsBaseUrl/api/remote.mux'),
        headers: _headers,
        pingInterval: const Duration(seconds: 20),
      );

      // 打开 $events 流
      _send({
        'type': 'open',
        'streamId': 'evt',
        'endpoint': r'$events',
        'payload': {'args': {}},
      });

      // 打开 session/follow 流
      //
      // Host 侧签名是 follow(request: SessionFollowRequest, signal)，
      // 生成客户端规则「单对象首参 → 线上字段名即参数名」，
      // 所以 args 里**必须有 request 包装层**：
      //   args: { request: { address, assistantStream, maxMessages } }
      // 缺了这层 Host 会因参数解析失败直接拒流（无历史、无流式）。
      if (sessionId != null && sessionId!.isNotEmpty) {
        _send({
          'type': 'open',
          'streamId': 'fol',
          'endpoint': 'session/follow',
          'payload': {
            'args': {
              'request': {
                'address': {
                  'kind': 'session',
                  'sessionId': sessionId,
                },
                'assistantStream': true,
                'maxMessages': 60,
              }
            }
          },
        });
      }

      // 打开 workspace/follow 流
      _send({
        'type': 'open',
        'streamId': 'wfo',
        'endpoint': 'workspace/follow',
        'payload': {'args': {}},
      });

      // 打开 session/control 流
      _send({
        'type': 'open',
        'streamId': 'ctl',
        'endpoint': 'session/control',
        'payload': {'args': {}},
      });

      _sub = _channel!.stream.listen(
        (d) => _onData(d),
        onDone: _onDone,
        onError: _onError,
        cancelOnError: false,
      );

      _reconnectAttempts = 0;
    } catch (e) {
      debugPrint('MuxStream connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _closeChannel() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    // clientId 与物理 socket 绑定，连接一断立即作废
    _clientId = null;
  }

  // ── 重连（指数退避）────

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _closeChannel();
    onReconnecting?.call();

    _reconnectAttempts++;
    final delay = _reconnectAttempts <= reconnectFastLimit
        ? Duration(seconds: reconnectFastDelaySec)
        : Duration(
            seconds: min(
              reconnectSlowDelaySec *
                  pow(2, _reconnectAttempts - reconnectFastLimit).toInt(),
              reconnectMaxDelaySec,
            ),
          );

    _reconnectTimer = Timer(delay, () {
      if (!_disposed) connect();
    });
  }

  void _onDone() {
    if (_disposed) return;
    _scheduleReconnect();
  }

  void _onError(Object error) {
    if (_disposed) return;
    debugPrint('MuxStream error: $error');
    onError?.call('$error');
    _scheduleReconnect();
  }
}
