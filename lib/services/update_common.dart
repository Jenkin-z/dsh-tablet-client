/// 更新域的平台无关类型（下载阶段与完整性校验异常）
library;

/// 完整性校验失败（借鉴 dsh-go fail-closed：声明了指纹就必须对上）
class UpdateVerifyException implements Exception {
  final String message;
  const UpdateVerifyException(this.message);
  @override
  String toString() => message;
}

/// 下载阶段（供 UI 展示「下载 → 校验 → 就绪」）
enum UpdateDlPhase { downloading, verifying }
