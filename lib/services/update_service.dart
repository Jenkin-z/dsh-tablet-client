import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../models/update_manifest.dart';
import '../utils/constants.dart';
import 'update_platform.dart';

export '../models/update_manifest.dart' show UpdateInfo;
export 'update_platform.dart' show UpdateDlPhase, UpdateVerifyException;

class UpdateCheckResult {
  final UpdateInfo? info;
  final String? error;
  const UpdateCheckResult._({this.info, this.error});
  factory UpdateCheckResult.update(UpdateInfo info) =>
      UpdateCheckResult._(info: info);
  factory UpdateCheckResult.latest() => const UpdateCheckResult._();
  factory UpdateCheckResult.failed(String error) =>
      UpdateCheckResult._(error: error);
}

/// 更新包在 DSH 同一台 PC 的 8099（version.json 与 dsh-agent.apk）
///
/// 检查更新是纯 http（全平台可用）；下载/安装是 Android 专属，
/// 委托给按平台条件编译的 [UpdatePlatform]（update_platform.dart）。
class UpdateService {
  static const int updatePort = 8099;
  static const String apkName = UpdatePlatform.apkName;
  static const String partSuffix = UpdatePlatform.partSuffix;
  static const String lastSuffix = UpdatePlatform.lastSuffix;

  static String baseUrl(String serverHost) => 'http://$serverHost:$updatePort';
  static String apkUrl(String serverHost) => '${baseUrl(serverHost)}/$apkName';

  static Future<UpdateCheckResult> checkHosts(Iterable<String> hosts) async {
    final seen = <String>{};
    String? lastError;
    var reached = false;
    final local = await PackageInfo.fromPlatform();
    final localCode = int.tryParse(local.buildNumber) ?? 0;
    for (final raw in hosts) {
      final host = raw.trim();
      if (host.isEmpty || !seen.add(host)) continue;
      try {
        final resp = await http
            .get(Uri.parse('${baseUrl(host)}/version.json'))
            .timeout(updateCheckTimeout);
        if (resp.statusCode != 200) {
          lastError = '$host:8099 HTTP ${resp.statusCode}';
          continue;
        }
        final raw = jsonDecode(resp.body);
        if (raw is! Map<String, dynamic>) {
          lastError = '$host:8099 version.json 不是对象';
          continue;
        }
        final manifest = UpdateManifest.tryParse(raw);
        if (manifest == null) {
          lastError = '$host:8099 version.json 不符合契约';
          continue;
        }
        reached = true;
        if (manifest.versionCode <= localCode) continue;
        return UpdateCheckResult.update(UpdateInfo(
          versionCode: manifest.versionCode,
          versionName: manifest.versionName,
          changelog: manifest.changelog,
          size: manifest.size,
          force: raw['force'] == true,
          url: (manifest.url?.isNotEmpty ?? false)
              ? manifest.url!
              : apkUrl(host),
          sha256: manifest.sha256,
        ));
      } catch (e) {
        lastError = '$host:8099 $e';
      }
    }
    if (reached) return UpdateCheckResult.latest();
    return UpdateCheckResult.failed(lastError ?? '没有可检查的更新地址');
  }

  static Future<String> currentVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return '${p.version} (${p.buildNumber})';
    } catch (_) {
      return '未知';
    }
  }

  /// 本地文件是否满足声明的完整性（CAS 命中判据）
  static Future<bool> fileMatches(
    dynamic f, {
    String? sha256,
    int size = 0,
  }) {
    return UpdatePlatform.fileMatches(f, sha256: sha256, size: size);
  }

  /// 事务化下载：临时文件 → 流式校验 → 原子替换（Android 专属）
  static Future<dynamic> download(
    String url,
    void Function(double progress) onProgress, {
    String? sha256,
    int size = 0,
    void Function(UpdateDlPhase phase)? onPhase,
  }) {
    return UpdatePlatform.download(
      url,
      onProgress,
      sha256: sha256,
      size: size,
      onPhase: onPhase,
    );
  }

  static Future<bool> canInstallUnknown() => UpdatePlatform.canInstallUnknown();

  static Future<void> openUnknownAppSources() =>
      UpdatePlatform.openUnknownAppSources();

  static Future<void> installApk(String path) =>
      UpdatePlatform.installApk(path);
}
