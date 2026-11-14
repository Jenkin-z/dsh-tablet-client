/// mux WebSocket 通道工厂（按平台条件导出）
///
/// Android/桌面用 IOWebSocketChannel（可带 Cookie 头、心跳 ping）；
/// Web 用浏览器原生 WebSocket（无自定义头，鉴权由 Host 侧另行处理）。
export 'mux_ws_stub.dart'
    if (dart.library.io) 'mux_ws_io.dart'
    if (dart.library.html) 'mux_ws_web.dart';
