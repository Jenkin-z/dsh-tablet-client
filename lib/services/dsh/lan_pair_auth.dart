import 'package:http/http.dart' as http;
import 'dsh_auth.dart';

/// dsh-lan-pair 插件的局域网配对授权（闸门端口默认 19387）
///
/// 插件契约（dsh-lan-pair/lib/routes.js + gate.js + proxy.js）：
/// 1) 换设备 cookie：`POST /__gate/pair` 表单 `code=<配对码>`，
///    扫码则 `GET /p/<码>`（二维码内容就是这个 URL）；
///    一码一机、300 秒有效，响应 200 + `Set-Cookie: lantg_device=...`
/// 2) 进会话入口：`GET /__gate/enter` 带设备 cookie → 302 → `/?token=...`
/// 3) 换 DSH 会话：`GET /?token=...` 带设备 cookie → 303 + `Set-Cookie: dsh-auth-*`
///
/// 之后 `/api` 与 WebSocket 同时带两个 cookie：lantg_device 过闸门、
/// dsh-auth-* 过 DSH 本体。拼成一串存进 AgentServer.cookie，
/// DshApi/MuxStream 原样放进 Cookie 头即可，模型与请求层零改动。
class LanPairAuth {
  /// 闸门端口；插件被占用时会走位到 19388+，地址里显式写端口即可
  static const defaultPort = 19387;

  /// 设备 cookie 名（插件配置 cookieName 的默认值）
  static const deviceCookieName = 'lantg_device';

  /// 解析手输地址：裸 IP/主机名默认 19387，可带 :port
  static PairTarget? parseAddress(String raw) =>
      NativeAuth.parse(raw, defaultPort: defaultPort);

  /// 解析扫码得到的配对链接 `http://IP:port/p/<码>`；不是则返回 null
  static ({String host, int port, String code})? parsePairLink(String raw) {
    final t = raw.trim();
    if (!t.startsWith('http://') && !t.startsWith('https://')) return null;
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty || uri.host.contains('%')) {
      return null;
    }
    if (!uri.path.startsWith('/p/')) return null;
    final code = uri.path.substring(3); // Uri.path 已解码，与插件端一致
    if (code.isEmpty) return null;
    int port;
    try {
      port = uri.hasPort ? uri.port : defaultPort;
    } catch (_) {
      return null; // 端口不是数字 / 溢出
    }
    return (host: uri.host, port: port, code: code);
  }

  /// 手输配对码授权：①POST 换设备 cookie → ②③换 DSH 会话
  static Future<AuthGrant> authorizeWithCode(
      PairTarget target, String code) async {
    final c = code.trim();
    if (c.isEmpty) {
      throw const DshAuthException(
        status: 400,
        unpaired: true,
        message: '请输入配对码（PC 管理页或 DSH 面板上显示的数字）',
      );
    }
    final device = await _redeem(
      target,
      () => http.Request(
        'POST',
        Uri(
          scheme: 'http',
          host: target.host,
          port: target.port,
          path: '/__gate/pair',
        ),
      )
        ..followRedirects = false
        ..headers['content-type'] = 'application/x-www-form-urlencoded'
        ..body = 'code=${Uri.encodeQueryComponent(c)}',
    );
    return _grant(target, device);
  }

  /// 扫码授权：qr 为 `http://IP:port/p/<码>`，GET 即兑换
  static Future<AuthGrant> authorizeFromQr(String qr) async {
    final link = parsePairLink(qr);
    if (link == null) {
      throw const DshAuthException(
        status: 400,
        unpaired: true,
        message: '不是有效的局域网配对二维码（应为 http://IP:19387/p/...）',
      );
    }
    final target = PairTarget(host: link.host, port: link.port);
    final device = await _redeem(
      target,
      () => http.Request(
        'GET',
        Uri(
          scheme: 'http',
          host: link.host,
          port: link.port,
          path: '/p/${Uri.encodeComponent(link.code)}',
        ),
      )..followRedirects = false,
    );
    return _grant(target, device);
  }

  /// 静默续期：设备 cookie 还有效时只走 ②③ 重换 DSH 会话，不再要配对码；
  /// 设备已被吊销时抛 unpaired，引导回配对码输入
  static Future<AuthGrant> renew(
          {required String host, required int port, required String deviceCookie}) =>
      _grant(PairTarget(host: host, port: port), deviceCookie);

  /// 从已存 cookie 串里取设备 cookie 段；返回 null 说明不是配对码授权
  static String? deviceCookieOf(String? cookie) {
    if (cookie == null || cookie.isEmpty) return null;
    for (final part in cookie.split(';')) {
      final eq = part.indexOf('=');
      if (eq == -1) continue;
      if (part.substring(0, eq).trim() == deviceCookieName) return part.trim();
    }
    return null;
  }

  /// 设备 cookie + ② enter + ③ token，拼出完整授权
  static Future<AuthGrant> _grant(PairTarget target, String deviceCookie) async {
    final session = await _enterAndMint(target, deviceCookie);
    return AuthGrant(
      host: target.host,
      port: target.port,
      cookie: '$deviceCookie; $session',
    );
  }

  /// 执行换设备 cookie 的请求，返回 lantg_device cookie 串
  static Future<String> _redeem(
      PairTarget target, http.Request Function() make) async {
    final client = http.Client();
    try {
      final resp = await client.send(make()).timeout(const Duration(seconds: 10));
      final setCookie = resp.headers['set-cookie'];
      final cookie =
          NativeAuth.cookieOf(setCookie, namePattern: deviceCookieName);
      if (resp.statusCode == 200 && cookie != null) return cookie;
      if (resp.statusCode == 401) {
        throw const DshAuthException(
          status: 401,
          unpaired: true,
          message: '配对码不正确、已过期或已作废：请在 PC 的管理页'
              '（http://127.0.0.1:<DSH端口>/__gate/admin）或 DSH 面板重新生成',
        );
      }
      throw DshAuthException(
        status: resp.statusCode,
        unpaired: true,
        message: resp.statusCode == 404
            ? '${target.host}:${target.port} 上没有配对服务：确认 PC 装了'
                ' dsh-lan-pair，端口看控制台 [dsh-lan-pair] 那行（默认19387，'
                '被占用会走位到19388+）'
            : '配对服务返回异常（HTTP ${resp.statusCode}）',
      );
    } on DshAuthException {
      rethrow;
    } catch (e) {
      throw DshAuthException(
        status: 0,
        unpaired: false,
        message: '连不上配对服务 ${target.host}:${target.port}'
            '（PC 上 DSH 和 dsh-lan-pair 在跑吗？）: $e',
      );
    } finally {
      client.close();
    }
  }

  /// ② 拿闸门签发的 DSH 一次性 token（302），③ 用它换 dsh-auth 会话（303）
  static Future<String> _enterAndMint(
      PairTarget target, String deviceCookie) async {
    final client = http.Client();
    try {
      final enter = http.Request(
        'GET',
        Uri(
          scheme: 'http',
          host: target.host,
          port: target.port,
          path: '/__gate/enter',
        ),
      )
        ..followRedirects = false
        ..headers['Cookie'] = deviceCookie;
      final enterResp = await client.send(enter).timeout(const Duration(seconds: 10));
      final location = enterResp.headers['location'];
      if (enterResp.statusCode != 302 || location == null || location.isEmpty) {
        if (enterResp.statusCode == 401) {
          throw const DshAuthException(
            status: 401,
            unpaired: true,
            message: '设备配对已失效（可能被吊销），请重新输入配对码',
          );
        }
        throw DshAuthException(
          status: enterResp.statusCode,
          unpaired: false,
          message: '获取会话入口失败（HTTP ${enterResp.statusCode}）',
        );
      }
      // Location 可能是绝对地址，也可能带路径；统一按闸门基址解析
      final tokenUri = Uri(scheme: 'http', host: target.host, port: target.port)
          .resolveUri(Uri.parse(location));
      final mint = http.Request('GET', tokenUri)
        ..followRedirects = false
        ..headers['Cookie'] = deviceCookie;
      final mintResp = await client.send(mint).timeout(const Duration(seconds: 15));
      final session = NativeAuth.cookieOf(mintResp.headers['set-cookie'],
          namePattern: NativeAuth.sessionCookieName);
      if (mintResp.statusCode != 303 || session == null) {
        throw DshAuthException(
          status: mintResp.statusCode,
          unpaired: mintResp.statusCode == 401,
          message: '换取 DSH 会话失败（HTTP ${mintResp.statusCode}），'
              'DSH 重启后旧会话会失效',
        );
      }
      return session;
    } on DshAuthException {
      rethrow;
    } catch (e) {
      throw DshAuthException(status: 0, unpaired: false, message: '换会话失败: $e');
    } finally {
      client.close();
    }
  }
}
