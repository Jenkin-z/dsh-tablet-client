import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/constants.dart';

/// opencode SSE 订阅：`GET /api/event`（Basic 鉴权，Accept: text/event-stream）
///
/// 帧格式（实测）：`data: {id, created?, type, location?, data, durable?}`，
/// 心跳行为 `: heartbeat`。本类只负责传输：
/// - 解析 SSE 帧 → [onEvent] 抛类型 + data；
/// - 断线指数退避重连（与 DSH mux 同一组退避参数）；
/// - 401/403 不重试（密码错了重试也没用），转 [onError] 后停止。
class OpenCodeStream {
  final String baseUrl;
  final String? password;

  /// 建连超时（可注入便于测试）；默认 [sseConnectTimeout]
  final Duration connectTimeout;

  OpenCodeStream({
    required this.baseUrl,
    this.password,
    this.connectTimeout = sseConnectTimeout,
  });

  /// 流（重）建立成功。首次连接与重连都会触发 —— 后端据此做全量对账。
  void Function()? onConnected;

  /// 流断开（尚未进入重试）
  void Function()? onDisconnected;

  /// 传输级错误（含授权失败）
  void Function(String message)? onError;

  /// 一个事件帧：type + data
  void Function(String type, Map<String, dynamic> data)? onEvent;

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Timer? _retryTimer;
  bool _disposed = false;
  int _attempts = 0;
  bool _authFailed = false;

  static const _user = 'opencode';

  Map<String, String> get _headers => <String, String>{
        'Accept': 'text/event-stream',
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_user:${password ?? ''}'))}',
      };

  bool get isConnected => _client != null && !_authFailed;

  void connect() {
    if (_disposed || _authFailed) return;
    _cancelRetry();
    _closeSub();
    // 重建 utf8 分块解码器并清空半截行：断线时残留的不完整序列
    // （字符被 TCP 边界劈开的瞬间）不应污染下一条流。
    _utf8 = utf8.decoder.startChunkedConversion(_DecodedTextSink(_onDecoded));
    _textBuffer.clear();
    _dataLines.clear();

    final client = http.Client();
    _client = client;
    final request = http.Request('GET', Uri.parse('$baseUrl/api/event'))
      ..headers.addAll(_headers);

    client
        .send(request)
        .timeout(connectTimeout)
        .then((resp) async {
      if (_disposed) {
        client.close();
        return;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        _authFailed = true;
        _client = null;
        client.close();
        onError?.call('opencode 授权失败：密码/令牌无效，请重新添加');
        return;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        client.close();
        _client = null;
        onError?.call('事件流连接失败（HTTP ${resp.statusCode}）');
        _scheduleRetry();
        return;
      }
      _attempts = 0;
      onConnected?.call();
      _sub = resp.stream.listen(
        _onBytes,
        onDone: _onDone,
        onError: _onStreamError,
        cancelOnError: false,
      );
    }).catchError((Object e) {
      if (_disposed) return;
      _client = null;
      // 挂死的半开连接必须显式掐断，否则 socket 泄漏
      client.close();
      onError?.call('事件流连接失败：$e');
      _scheduleRetry();
    });
  }

  void dispose() {
    _disposed = true;
    _cancelRetry();
    _closeSub();
    _client?.close();
    _client = null;
  }

  void _closeSub() {
    _sub?.cancel();
    _sub = null;
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _onDone() {
    if (_disposed) return;
    _closeSub();
    _client?.close();
    _client = null;
    onDisconnected?.call();
    _scheduleRetry();
  }

  void _onStreamError(Object error) {
    if (_disposed) return;
    _closeSub();
    _client?.close();
    _client = null;
    onError?.call('事件流错误：$error');
    _scheduleRetry();
  }

  /// 指数退避：前 5 次 3s，之后 30s 起翻倍，上限 60s（与 DSH mux 同参）
  void _scheduleRetry() {
    if (_disposed || _authFailed) return;
    _cancelRetry();
    _attempts++;
    var secs = reconnectFastDelaySec;
    if (_attempts > reconnectFastLimit) {
      secs = reconnectSlowDelaySec;
      for (var i = reconnectFastLimit + 1; i < _attempts; i++) {
        if (secs >= reconnectMaxDelaySec) break;
        secs *= 2;
      }
    }
    if (secs > reconnectMaxDelaySec) secs = reconnectMaxDelaySec;
    _retryTimer = Timer(Duration(seconds: secs), connect);
  }

  // ── SSE 帧解析 ───────────────────────────────────

  final List<String> _dataLines = [];
  final StringBuffer _textBuffer = StringBuffer();

  /// utf8 流式解码：多字节字符（中文）被 TCP chunk 边界劈开时不会变成
  /// U+FFFD 替换符——打字机增量里出现中文是常态。
  /// 每次 connect 重建（见 [connect]），半截序列不跨流残留。
  late ByteConversionSink _utf8;

  void _onBytes(List<int> chunk) {
    _utf8.add(chunk);
  }

  void _onDecoded(String text) {
    // 手动切行：解码后的文本边界仍可能落在一行中间，只有见到 \n
    // 才算完整行，剩下的尾巴留在缓冲区等下一个 chunk。
    _textBuffer.write(text);
    final all = _textBuffer.toString();
    var start = 0;
    for (var i = 0; i < all.length; i++) {
      if (all.codeUnitAt(i) != 0x0A) continue; // \n
      var end = i;
      if (end > start && all.codeUnitAt(end - 1) == 0x0D) end--; // \r\n
      _onLine(all.substring(start, end));
      start = i + 1;
    }
    final rest = all.substring(start);
    _textBuffer.clear();
    _textBuffer.write(rest);
  }

  void _onLine(String line) {
    if (line.isEmpty) {
      _flushFrame();
      return;
    }
    if (line.startsWith(':')) return; // 心跳/注释
    if (line.startsWith('data:')) {
      var payload = line.substring(5);
      if (payload.startsWith(' ')) payload = payload.substring(1);
      _dataLines.add(payload);
    }
    // event:/id:/retry: 字段 opencode 未使用，忽略
  }

  void _flushFrame() {
    if (_dataLines.isEmpty) return;
    final body = _dataLines.join('\n');
    _dataLines.clear();
    if (body.trim().isEmpty) return;
    try {
      final data = jsonDecode(body);
      if (data is! Map) return;
      final type = data['type'] as String?;
      if (type == null || type.isEmpty) return;
      final payload = data['data'];
      onEvent?.call(
        type,
        payload is Map<String, dynamic>
            ? payload
            : (payload is Map ? payload.cast<String, dynamic>() : const {}),
      );
    } catch (_) {
      // 半截 JSON（连接被切断的瞬间）直接丢弃，等下一帧
    }
  }
}

/// utf8 分块解码的文本出口：把解码出的字符串段转给 [OpenCodeStream._onDecoded]
class _DecodedTextSink implements Sink<String> {
  _DecodedTextSink(this._onText);

  final void Function(String text) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}
