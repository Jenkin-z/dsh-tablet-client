/// 更新清单契约与更新信息模型（借鉴 dsh-go Release Descriptor V2）
///
/// 设计原则（源自 dsh-go 的发布完整性思想）：
/// - **fail-closed 解析**：清单里声明了完整性字段（sha256/size）却不合法，
///   直接判无效，绝不过半信半疑的数据往下走。
/// - **声明 ≠ 已验证**：`sha256` 只是发布方声明，必须等下载完成逐字节校验
///   通过才算数；校验前 UI 只展示「指纹」不展示「已验证」。
/// - **向后兼容**：老 version.json（无 sha256）继续可用，退化为 size 校验。
library;

/// version.json 的结构化契约（PC 8099 分发目录）
class UpdateManifest {
  final int versionCode;
  final String versionName;
  final String changelog;

  /// 声明的包大小（字节）；0/缺省表示未声明
  final int size;

  /// 声明的 SHA-256（64 位十六进制，统一小写）；null 表示未声明
  final String? sha256;
  final String? url;

  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.changelog,
    required this.size,
    this.sha256,
    this.url,
  });

  bool get integrityDeclared => sha256 != null || size > 0;

  /// 展示用指纹短码（前 12 位），如 `a1b2c3d4e5f6`
  String? get fingerprintShort =>
      sha256 == null ? null : sha256!.substring(0, 12);

  /// 契约校验 + 解析。不满足契约返回 null，调用方按「清单无效」处理。
  ///
  /// 契约：
  /// - versionCode 必须是正整数（比较基准，缺了没有意义）
  /// - sha256 声明了就必须是 64 位十六进制（否则 fail-closed 判无效）
  /// - size 声明了就必须是非负数
  static UpdateManifest? tryParse(Map<String, dynamic> json) {
    final code = (json['versionCode'] as num?)?.toInt() ?? 0;
    if (code <= 0) return null;
    final rawSha = (json['sha256'] as String?)?.trim().toLowerCase() ?? '';
    if (rawSha.isNotEmpty && !_isSha256Hex(rawSha)) return null;
    final size = (json['size'] as num?)?.toInt() ?? 0;
    if (size < 0) return null;
    return UpdateManifest(
      versionCode: code,
      versionName: json['versionName'] as String? ?? '$code',
      changelog: json['changelog'] as String? ?? '常规更新',
      size: size,
      sha256: rawSha.isEmpty ? null : rawSha,
      url: json['url'] as String?,
    );
  }

  static bool _isSha256Hex(String s) =>
      s.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(s);
}

/// 面向 UI 的更新信息（由 [UpdateManifest] 转化，已通过与本地版本的比较）
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String changelog;
  final int size;
  final bool force;
  final String url;

  /// 发布方声明的 SHA-256；null 表示分发目录还没提供（退化为 size 校验）
  final String? sha256;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.changelog,
    required this.size,
    required this.force,
    required this.url,
    this.sha256,
  });

  String get sizeText =>
      size > 0 ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB' : '未知大小';

  String? get fingerprintShort =>
      sha256 == null ? null : sha256!.substring(0, 12);
}
