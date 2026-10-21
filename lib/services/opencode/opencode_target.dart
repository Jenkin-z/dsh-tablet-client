import 'dart:convert';

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

/// 解析用户输入：完整授权链接 / 普通 URL / 裸 host:port / 配对二维码 JSON
///
/// 支持任意 IP / 主机名 / IPv6 / 尾斜杠 / 带路径——裸输入统一补 http://
/// 交给 Uri 解析，不限定点分十进制格式：
/// 1. 配对二维码：`opencode pair` 打印的二维码内容是 JSON
///    `{"code":"<码>","urls":["<基址>"]}`（实测 opencode 2.1.2）；
/// 2. 授权链接：`https://<隧道域名>/auth/connect/<code>`（码 300s 有效）；
/// 3. 普通 URL：`http://<ip>:4096`（可带路径，只取 scheme+host+port）；
/// 4. 裸 host:port：`0.0.0.0:4096` / `myhost` / `[::1]:4096`（默认 4096）。
///
/// 认不出的输入返回 null（调用方给错误提示，不猜）。
///
/// 扫码拿到的原文常带说明文字或多行（`opencode pair` 会把本地和隧道两条
/// 链接一起打印），整串解析不成立时退化为「取正文里的 URL」。
OpenCodeTarget? parseOpenCodeTarget(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  // 配对二维码是 JSON 载荷（不是链接），走单独分支
  if (t.startsWith('{')) return _parsePairPayload(t);
  final direct = _parseSingle(t);
  if (direct != null) return direct;
  final url = _firstUrl(t);
  return url == null ? null : _parseSingle(url);
}

/// 解析 `opencode pair` 的二维码载荷：
/// `{"code":"<授权码>","urls":["<基址>","..."]}`
///
/// 基址在 `urls` 里（可多条，含 /auth/connect 路径时取 scheme+host+port）。
/// 认不出的形状返回 null。
OpenCodeTarget? _parsePairPayload(String t) {
  Object? decoded;
  try {
    decoded = jsonDecode(t);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final code = decoded['code'];
  if (code is! String || code.trim().isEmpty) return null;
  final urls = <String>[];
  final rawUrls = decoded['urls'];
  if (rawUrls is List) {
    for (final u in rawUrls) {
      if (u is String && u.trim().isNotEmpty) urls.add(u.trim());
    }
  }
  final single = decoded['url'];
  if (single is String && single.trim().isNotEmpty) urls.add(single.trim());
  if (urls.isEmpty) return null;
  final base = _pickBaseUrl(urls);
  if (base == null) return null;
  return OpenCodeTarget(
    baseUrl: base.baseUrl,
    host: base.host,
    port: base.port,
    pairCode: code.trim(),
  );
}

/// 多条基址里挑一条平板能连的：优先 https 隧道，其次非回环地址。
OpenCodeTarget? _pickBaseUrl(List<String> urls) {
  final parsed = urls.map(_parseSingle).whereType<OpenCodeTarget>().toList();
  if (parsed.isEmpty) return null;
  for (final p in parsed) {
    if (p.baseUrl.startsWith('https://') && !isLoopbackHost(p.host)) {
      return p;
    }
  }
  for (final p in parsed) {
    if (!isLoopbackHost(p.host)) return p;
  }
  return parsed.first;
}

/// 回环地址：扫到也连不上（那指的是 PC 自己，不是平板）
bool isLoopbackHost(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' ||
      h == '::1' ||
      h == '0.0.0.0' ||
      h.startsWith('127.');
}

/// 正文里第一个可用 URL：优先 https——多行时本地 `http://127.0.0.1`
/// 排在前面，平板只有隧道地址连得上
String? _firstUrl(String text) {
  String? plain;
  for (final m in RegExp(r'https?://\S+').allMatches(text)) {
    // 正文里 URL 后可能跟标点
    final url = m.group(0)!.replaceFirst(RegExp(r'[.,;:]+$'), '');
    if (url.startsWith('https://')) return url;
    plain ??= url;
  }
  return plain;
}

/// 整串当作单个 URL / host:port 解析。
/// 含换行的「整串」其实是多段文本，直解只会解出乱码
/// （曾把两行链接解成 `baseUrl=http://http`），拒绝后交给 [_firstUrl]。
OpenCodeTarget? _parseSingle(String t) {
  if (t.contains('\n') || t.contains('\r')) return null;
  // 输入分派：`word://` 是完整 URL；`word:数字` 是被误认成 scheme 的
  // host:port（如 myhost:4096/x）；其余裸输入统一补 http:// 交给 Uri
  final sm = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):(.*)$').firstMatch(t);
  final String toParse;
  if (sm == null) {
    toParse = 'http://$t';
  } else if (sm.group(2)!.startsWith('//')) {
    toParse = t;
  } else if (RegExp(r'^\d').hasMatch(sm.group(2)!)) {
    toParse = 'http://$t';
  } else {
    toParse = t; // http:/x 之类的坏 URL：解析不出 host，走 null
  }
  final uri = Uri.tryParse(toParse);
  if (uri == null || uri.host.isEmpty || uri.host.contains('%')) {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  int port;
  try {
    port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 4096);
  } catch (_) {
    return null; // 端口不是数字 / 溢出
  }
  if (port <= 0 || port > 65535) return null;
  // IPv6 的 Uri.host 不带方括号，重组 URL 时要补回
  final hostPart = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final base = '${uri.scheme}://$hostPart'
      '${uri.hasPort ? ':$port' : ''}';
  final m = RegExp(r'/auth/connect/([^/?#]+)').firstMatch(uri.path);
  return OpenCodeTarget(
    baseUrl: base,
    host: uri.host,
    port: port,
    pairCode: m?.group(1),
  );
}
