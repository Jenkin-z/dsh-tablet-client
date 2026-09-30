import 'dart:convert';
import 'package:http/http.dart' as http;

/// 授权失败（401 cookie 过期，需重新换取）
class DshAuthException implements Exception {
  final int status;
  final bool unpaired;
  final String message;

  const DshAuthException({
    required this.status,
    required this.unpaired,
    required this.message,
  });

  @override
  String toString() => message;
}

/// 解析出的 PC 目标（IP:端口，可带启动令牌）
class PairTarget {
  final String host;
  final int port;
  final String? token;

  const PairTarget({required this.host, this.port = 3080, this.token});

  /// 指向 8899 配对页（新方案），而不是 DSH 本体
  bool get isPairServer =>
      (token == null || token!.isEmpty) && port == NativeAuth.pairPort;
}

/// 授权结果：DSH 本体地址 + cookie
class AuthGrant {
  final String host;
  final int port;
  final String cookie;

  const AuthGrant({
    required this.host,
    required this.port,
    required this.cookie,
  });
}

/// DSH 原生 browser-session 授权（无需配对插件）
///
/// 1) PC 每次 `dsh web` 启动会打印一次性启动令牌：`http://...:3080/?token=r_...`
/// 2) `GET /?token=<启动令牌>` → 303 + `Set-Cookie: dsh-auth-*=...`
/// 3) 之后所有 `/api` 请求带这个 cookie；默认 30 天，DSH 重启后仍有效
///
/// 新方案（8899 配对页，PC 双击「手机授权.bat」）：
/// `GET :8899/go?ip=<PC IP>` → 302 + `Set-Cookie: dsh-auth-*` + `Location: http://IP:19387/`
/// cookie 由 PC 用持久 secret 自签，绑定 `IP:19387`，与启动令牌无关
class NativeAuth {
  static const pairPort = 8899;
  static const _desktopPort = 19387;
  static final _cookieRe = RegExp(r'(dsh-auth-[^=;\s]+)=([^;\s,]+)');

  /// 统一入口：带 token 走旧链路，指向 8899 走配对页
  static Future<AuthGrant> authorize(PairTarget target) async {
    if (target.token != null && target.token!.isNotEmpty) {
      final cookie = await exchangeCookie(target);
      return AuthGrant(host: target.host, port: target.port, cookie: cookie);
    }
    if (target.port == pairPort) {
      return fetchFromPairServer(target.host, port: target.port);
    }
    throw const DshAuthException(
      status: 400,
      unpaired: true,
      message: '无法授权：请粘贴带 ?token= 的启动链接，或 8899 配对页地址（http://IP:8899/）',
    );
  }

  /// 新方案：从 8899 配对页领取自签 cookie。
  /// [host] 必须是 PC 某块网卡的 IPv4（配对页按 IP 签发，cookie 绑定该地址）。
  static Future<AuthGrant> fetchFromPairServer(String host,
      {int port = pairPort}) async {
    final client = http.Client();
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/go',
        queryParameters: {'ip': host},
      );
      final req = http.Request('GET', uri)..followRedirects = false;
      final resp = await client.send(req).timeout(const Duration(seconds: 10));
      final setCookie = resp.headers['set-cookie'];
      final isRedirect = resp.statusCode == 302 || resp.statusCode == 303;
      if (!isRedirect || setCookie == null) {
        throw DshAuthException(
          status: resp.statusCode,
          unpaired: true,
          message: resp.statusCode == 404
              ? '配对页不认识 $host：请填 PC 的局域网 IP（不要用主机名）'
              : '配对页返回异常（HTTP ${resp.statusCode}）',
        );
      }
      final pair = _cookieRe.firstMatch(setCookie);
      if (pair == null) {
        throw const DshAuthException(
          status: 500,
          unpaired: true,
          message: '配对页响应里没有 dsh-auth cookie',
        );
      }
      final loc = Uri.tryParse(resp.headers['location'] ?? '');
      final dshPort =
          (loc != null && loc.hasPort) ? loc.port : _desktopPort;
      return AuthGrant(
        host: host,
        port: dshPort,
        cookie: '${pair.group(1)}=${pair.group(2)}',
      );
    } on DshAuthException {
      rethrow;
    } catch (e) {
      throw DshAuthException(
        status: 0,
        unpaired: false,
        message: '连不上配对页 $host:$port（PC 上双击「手机授权.bat」了吗？）: $e',
      );
    } finally {
      client.close();
    }
  }

  static PairTarget? parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('http')) {
      final uri = Uri.tryParse(t);
      if (uri != null && uri.host.isNotEmpty) {
        return PairTarget(
          host: uri.host,
          port: uri.hasPort ? uri.port : 3080,
          token: uri.queryParameters['token'],
        );
      }
      return null;
    }
    final hp = RegExp(r'^([\w.-]+):(\d+)$').firstMatch(t);
    if (hp != null) {
      return PairTarget(host: hp.group(1)!, port: int.parse(hp.group(2)!));
    }
    if (RegExp(r'^[\w.-]+$').hasMatch(t)) {
      return PairTarget(host: t);
    }
    return null;
  }

  /// 用启动令牌换取 browser cookie。返回 "name=value"，原样放进 Cookie 头。
  static Future<String> exchangeCookie(PairTarget target) async {
    final token = target.token;
    if (token == null || token.isEmpty) {
      throw const DshAuthException(
        status: 400,
        unpaired: true,
        message: '缺少启动令牌：请粘贴 dsh web 启动输出里 ?token= 后面的完整链接或令牌',
      );
    }
    final client = http.Client();
    try {
      final req = http.Request(
        'GET',
        Uri.parse('http://${target.host}:${target.port}/?token=$token'),
      )..followRedirects = false;
      final resp = await client.send(req).timeout(const Duration(seconds: 15));
      final setCookie = resp.headers['set-cookie'];
      if (resp.statusCode != 303 || setCookie == null) {
        throw DshAuthException(
          status: resp.statusCode,
          unpaired: true,
          message: '启动令牌无效或已过期（HTTP ${resp.statusCode}）。'
              'DSH 重启后令牌会变，请用最新一次启动输出的令牌。',
        );
      }
      final pair = _cookieRe.firstMatch(setCookie);
      if (pair == null) {
        throw const DshAuthException(
          status: 500,
          unpaired: true,
          message: '授权响应里没有找到 dsh-auth cookie',
        );
      }
      return '${pair.group(1)}=${pair.group(2)}';
    } on DshAuthException {
      rethrow;
    } catch (e) {
      throw DshAuthException(
        status: 0,
        unpaired: false,
        message: '换取授权失败: $e',
      );
    } finally {
      client.close();
    }
  }

  /// 从 PC 的 8099 中转服务读取最新启动令牌（全自动，无需手动传）
  static Future<PairTarget> fetchFromRelay(String host, {int port = 8099}) async {
    final resp = await http
        .get(Uri.parse('http://$host:$port/launch-token.json'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw DshAuthException(
        status: resp.statusCode,
        unpaired: false,
        message: '8099 上没有 launch-token.json，'
            '请在 PC 上运行 tool\\publish_launch_token.ps1',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const DshAuthException(
        status: 500,
        unpaired: false,
        message: 'launch-token.json 里没有 token',
      );
    }
    return PairTarget(host: host, port: 3080, token: token);
  }
}
