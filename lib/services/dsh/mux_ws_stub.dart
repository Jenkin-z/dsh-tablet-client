import 'package:web_socket_channel/web_socket_channel.dart';

/// 兜底实现（当前 Flutter 目标平台必然命中 io 或 web 分支）
WebSocketChannel connectMuxChannel(
  Uri uri, {
  Map<String, String>? headers,
  Duration? pingInterval,
}) {
  return WebSocketChannel.connect(uri);
}
