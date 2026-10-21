part of 'dsh_auth.dart';

// 授权模块的辅助类型（DshAuthException / PairTarget / AuthGrant）
//
// 放在 part 文件里是同库共享作用域：外部仍然只需
// `import 'dsh_auth.dart'` 就能拿到这三个公开类型，
// 对外 API 与拆分前完全一致；只是把「类型定义」与
// 「授权流程（NativeAuth）」分开，便于各自阅读。
//
// 注意：part 文件不能写 import 语句（与主文件共享 import 作用域），
// 这里也不需要任何 import。

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
