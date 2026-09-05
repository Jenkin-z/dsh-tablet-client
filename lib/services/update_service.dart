import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内更新：查 version.json → 下载 APK → 调系统安装器
/// 更新服务器 = DSH 同一台 PC，固定端口 8099（version.json 与 dsh-agent.apk 同目录）
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String changelog;
  final int size;
  final bool force;
  final String url;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.changelog,
    required this.size,
    required this.force,
    required this.url,
  });

  String get sizeText => size > 0
      ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
      : '未知大小';
}

class UpdateService {
  static const int updatePort = 8099;
  static const String apkName = 'dsh-agent.apk';
  static const MethodChannel _channel = MethodChannel('dsh.agent/update');

  static String baseUrl(String serverHost) => 'http://$serverHost:$updatePort';
  static String apkUrl(String serverHost) => '${baseUrl(serverHost)}/$apkName';

  /// 有新版返回 UpdateInfo，否则返回 null（网络失败也返回 null，不打扰）
  static Future<UpdateInfo?> check(String serverHost) async {
    try {
      final local = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(local.buildNumber) ?? 0;
      final resp = await http
          .get(Uri.parse('${baseUrl(serverHost)}/version.json'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final remoteCode = (j['versionCode'] as num?)?.toInt() ?? 0;
      if (remoteCode <= localCode) return null;
      return UpdateInfo(
        versionCode: remoteCode,
        versionName: j['versionName'] as String? ?? '$remoteCode',
        changelog: j['changelog'] as String? ?? '常规更新',
        size: (j['size'] as num?)?.toInt() ?? 0,
        force: j['force'] == true,
        url: (j['url'] as String?)?.isNotEmpty == true
            ? j['url'] as String
            : apkUrl(serverHost),
      );
    } catch (_) {
      return null;
    }
  }

  /// 当前版本字符串（设置页展示用）
  static Future<String> currentVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return '${p.version} (${p.buildNumber})';
    } catch (_) {
      return '未知';
    }
  }

  /// 流式下载，progress 0~1；返回存好的 APK 文件
  static Future<File> download(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await _updateDir();
    final dest = File('${dir.path}/$apkName');
    if (await dest.exists()) await dest.delete();

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('下载失败：HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      var got = 0;
      final sink = dest.openWrite();
      try {
        await for (final chunk in resp) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(total > 0 ? got / total : 0);
        }
      } finally {
        await sink.close();
      }
      onProgress(1);
      return dest;
    } finally {
      client.close();
    }
  }

  static Future<Directory> _updateDir() async {
    final base = await getExternalStorageDirectory() ??
        await getTemporaryDirectory();
    final dir = Directory('${base.path}/updates');
    await dir.create(recursive: true);
    return dir;
  }

  /// 是否已允许“安装未知应用”
  static Future<bool> canInstallUnknown() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallUnknown') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到本应用的“安装未知应用”开关页
  static Future<void> openUnknownAppSources() async {
    try {
      await _channel.invokeMethod('openUnknownAppSources');
    } catch (_) {}
  }

  /// 调起系统安装器
  static Future<void> installApk(String path) async {
    await _channel.invokeMethod('installApk', {'path': path});
  }
}
