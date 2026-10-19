/// 解析出的 opencode 目标
class OpenCodeTarget {
  /// http(s)://host[:port]，作为 AgentServer.url（权威基址）
  final String baseUrl;

  /// 展示/旧数据迁移用
  final String host;
  final int port;

  /// 授权链接里的 `/auth/connect/<code>`（手动连接模式为 null）
  final String? pairCode;

  const OpenCodeTarget({
    required this.baseUrl,
    required this.host,
    required this.port,
    this.pairCode,
  });
}

/// 解析用户输入：完整授权链接 / 普通 URL / 裸 host:port
///
/// 三种形态都来自真实使用场景：
/// 1. 授权链接：`opencode pair --remote` 输出的
///    `https://<隧道域名>/auth/connect/<code>`（码 300s 有效）；
/// 2. 普通 URL：`http://192.168.10.x:4096`（可带路径，只取 scheme+host+port）；
/// 3. 裸 host:port：`192.168.10.x:4096` 或 `192.168.10.x`（默认 4096）。
///
/// 认不出的输入返回 null（调用方给错误提示，不猜）。
OpenCodeTarget? parseOpenCodeTarget(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (!t.startsWith('http://') && !t.startsWith('https://')) {
    if (RegExp(r'^[\w.-]+(:\d+)?$').hasMatch(t)) {
      final hp = t.split(':');
      return OpenCodeTarget(
        baseUrl: 'http://$t',
        host: hp[0],
        port: hp.length > 1 ? int.tryParse(hp[1]) ?? 4096 : 4096,
      );
    }
    return null;
  }
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty) return null;
  final base = '${uri.scheme}://${uri.host}'
      '${uri.hasPort ? ':${uri.port}' : ''}';
  final m = RegExp(r'/auth/connect/([^/?#]+)').firstMatch(uri.path);
  return OpenCodeTarget(
    baseUrl: base,
    host: uri.host,
    port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 4096),
    pairCode: m?.group(1),
  );
}
