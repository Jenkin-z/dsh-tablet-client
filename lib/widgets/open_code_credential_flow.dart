import 'package:flutter/material.dart';

import '../screens/qr_scan_screen.dart';
import '../services/opencode/opencode_api.dart';
import '../services/opencode/opencode_target.dart';

/// 添加 opencode 的凭据获取流程（换码 / 验密码 / 扫码填入）
///
/// 从 add_opencode_dialog.dart 拆出来，让那个文件守住 200 行上限。
/// 每一步的失败信息通过 [onError] 上抛，由对话框原地显示。
class OpenCodeCredentialFlow {
  /// 授权链接模式：换码；手动模式：先验密码
  bool linkMode;

  /// 手动模式的服务密码
  final String password;

  /// 失败时回调（写进对话框的错误位）
  final void Function(String message) onError;

  OpenCodeCredentialFlow({
    required this.linkMode,
    required this.password,
    required this.onError,
  });

  /// 按模式取令牌：授权链接换码 / 手动连接先验再存。
  /// 失败时写错误信息并返回 null。
  Future<String?> acquireToken(OpenCodeTarget target) async {
    if (linkMode) {
      final code = target.pairCode;
      if (code == null) {
        onError('链接里没有授权码：请粘贴 opencode pair --remote 输出的完整链接');
        return null;
      }
      return OpenCodeApi(baseUrl: target.baseUrl).exchangePairCode(code);
    }
    final password = this.password.trim();
    if (password.isEmpty) {
      onError('请填服务密码（PC 端 opencode serve 的 OPENCODE_SERVER_PASSWORD）');
      return null;
    }
    // 先验再存：密码错当场说，别存一个连不上的条目
    final ok = await OpenCodeApi(baseUrl: target.baseUrl, password: password)
        .testConnection();
    if (!ok) {
      onError('连不上 $target.baseUrl：PC 上 opencode serve 起了吗？');
      return null;
    }
    return password;
  }
}

/// 扫码填入：授权二维码（含 /auth/connect/<code>）→ 链接模式；
/// 局域网地址二维码 → 手动模式。识别不出给错误提示。
///
/// 从 add_opencode_dialog.dart 拆出来，让那个文件守住 200 行上限。
/// 取消扫码返回 null；识别不出走 [onError] 并返回 null。
Future<OpenCodeTarget?> scanOpenCodeTarget(
  BuildContext context, {
  required void Function(String message) onError,
}) async {
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          const QrScanScreen(expect: QrScanExpect.opencodeLink),
    ),
  );
  if (raw == null) return null;
  final target = parseOpenCodeTarget(raw);
  if (target == null) {
    onError('扫到的内容不是有效的 opencode 地址');
    return null;
  }
  return target;
}
