import 'update_common.dart';
export 'update_common.dart';

/// Web 平台占位：应用内更新是 Android APK 专属能力
///
/// 检查更新（checkHosts，纯 http）仍可用；下载/安装直接拒绝。
class UpdatePlatform {
  static const String apkName = 'dsh-agent.apk';
  static const String partSuffix = '.part';
  static const String lastSuffix = '.last.apk';

  static Future<bool> fileMatches(dynamic f, {String? sha256, int size = 0}) =>
      Future.value(false);

  static Future<dynamic> download(
    String url,
    void Function(double progress) onProgress, {
    String? sha256,
    int size = 0,
    void Function(UpdateDlPhase phase)? onPhase,
  }) async {
    throw UnsupportedError('Web 端不支持应用内更新，请在 PC 上直接下载安装包');
  }

  static Future<bool> canInstallUnknown() async => false;

  static Future<void> openUnknownAppSources() async {}

  static Future<void> installApk(String path) async {
    throw UnsupportedError('Web 端不支持安装 APK');
  }
}
