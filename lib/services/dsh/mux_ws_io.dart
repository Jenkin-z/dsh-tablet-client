import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// IO 平台实现：可带自定义头（Cookie）+ 心跳 ping
WebSocketChannel connectMuxChannel(
  Uri uri, {
  Map<String, String>? headers,
  Duration? pingInterval,
}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: pingInterval,
  );
}
