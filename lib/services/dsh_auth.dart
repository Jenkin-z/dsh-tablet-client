import 'dart:convert';
import 'package:http/http.dart' as http;

/// 鉴权/配对失败（401 未登录，403 未配对或被撤销）
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

/// 扫码/粘贴解析出的目标
class PairTarget {
  final String host;
  final int port;
  final String? token;

  const PairTarget({required this.host, this.port = 3080, this.token});
}

/// 官方 remote-web-ui 配对：LAN 直打 /api/pair/*，不走 /remote
class PairingClient {
  static const cookieName = 'dsh_pair';

  static PairTarget? parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final uri = Uri.tryParse(t);
    if (uri != null && uri.host.isNotEmpty && (uri.scheme == 'http' ||
        uri.scheme == 'https' || t.startsWith('http'))) {
      return PairTarget(
        host: uri.host,
        port: uri.hasPort ? uri.port : 3080,
        token: uri.queryParameters['pair'],
      );
    }
    // 纯令牌
    final token = RegExp(r'^[0-9a-fA-F]{32}$').firstMatch(t);
    if (token != null) {
      return PairTarget(host: '192.168.10.171', port: 3080, token: t);
    }
    // IP:port
    final hp = RegExp(r'^([\w.-]+):(\d+)$').firstMatch(t);
    if (hp != null) {
      return PairTarget(host: hp.group(1)!, port: int.parse(hp.group(2)!));
    }
    return null;
  }

  /// POST /api/pair/accept → deviceId；token 约 10 分钟有效
  static Future<String> accept(PairTarget target) async {
    final token = target.token;
    if (token == null || token.isEmpty) {
      throw const DshAuthException(
        status: 400,
        unpaired: true,
        message: '链接里没有 pair 参数，请扫描 PC 上的配对二维码',
      );
    }
    final resp = await http
        .post(
          Uri.parse('http://${target.host}:${target.port}/api/pair/accept'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 404) {
      throw const DshAuthException(
        status: 404,
        unpaired: false,
        message: '这台 DSH 没有配对插件，可直接用 IP 添加',
      );
    }
    if (resp.statusCode != 200) {
      throw DshAuthException(
        status: resp.statusCode,
        unpaired: true,
        message: _acceptError(resp),
      );
    }
    final data = jsonDecode(resp.body);
    if (data is Map<String, dynamic> && data['ok'] == true) {
      final id = data['deviceId'] as String?;
      if (id != null && id.isNotEmpty) return id;
    }
    throw DshAuthException(
      status: resp.statusCode,
      unpaired: true,
      message: _acceptError(resp),
    );
  }

  static String _acceptError(http.Response resp) {
    try {
      final data = jsonDecode(resp.body);
      if (data is Map && data['code'] is String) {
        switch (data['code']) {
          case 'invalid':
            return '二维码已过期或无效，请在 PC 上刷新后再扫';
          case 'used':
            return '这个二维码已经用过，请在 PC 上刷新';
          case 'rate-limited':
            return '尝试太频繁，稍后再扫';
          case 'forbidden':
            return '不在同一局域网，无法配对';
        }
      }
    } catch (_) {}
    return '配对失败 HTTP ${resp.statusCode}';
  }

  static Future<void> heartbeat(String host, int port, String deviceId) async {
    final resp = await http
        .post(
          Uri.parse('http://$host:$port/api/pair/heartbeat'),
          headers: {
            'Content-Type': 'application/json',
            'Cookie': '$cookieName=$deviceId',
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw DshAuthException(
        status: resp.statusCode,
        unpaired: true,
        message: '配对已失效，需要重新扫码',
      );
    }
  }

  /// 探测是否装了配对插件。404 = 老 DSH，可直连 /api
  static Future<bool> pluginPresent(String host, int port) async {
    try {
      final resp = await http
          .get(Uri.parse('http://$host:$port/api/pair/status'))
          .timeout(const Duration(seconds: 8));
      return resp.statusCode != 404;
    } catch (_) {
      return false;
    }
  }
}
