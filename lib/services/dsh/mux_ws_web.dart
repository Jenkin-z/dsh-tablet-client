import 'package:web_socket_channel/web_socket_channel.dart';

/// Web 平台实现：浏览器原生 WebSocket（无自定义头/心跳配置）
WebSocketChannel connectMuxChannel(
  Uri uri, {
  Map<String, String>? headers,
  Duration? pingInterval,
}) {
  return WebSocketChannel.connect(uri);
}
