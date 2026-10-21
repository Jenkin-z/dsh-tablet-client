import 'dart:convert';
import 'package:http/http.dart' as http;

import 'dsh_auth.dart';

/// 从 PC 的 8099 中转服务读取最新启动令牌（全自动，无需手动传）
///
/// 与 [NativeAuth] 的授权主流程分开：这条链路不碰 Host，
/// 只从 PC 本地的中转服务拿一次令牌，拿到后仍走标准授权流程。
class NativeAuthRelay {
  const NativeAuthRelay._();

  static Future<PairTarget> fetchFromRelay(String host,
      {int port = 8099}) async {    final resp = await http
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
