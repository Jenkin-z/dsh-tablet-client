import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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
class UpdateService {
  static const int updatePort = 8099;
  static const String apkName = 'dsh-agent.apk';
  static const MethodChannel _channel = MethodChannel('dsh.agent/update');

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
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) {
          lastError = '$host:8099 HTTP ${resp.statusCode}';
          continue;
        }
        reached = true;
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final remoteCode = (j['versionCode'] as num?)?.toInt() ?? 0;
        if (remoteCode <= localCode) continue;
        return UpdateCheckResult.update(UpdateInfo(
          versionCode: remoteCode,
          versionName: j['versionName'] as String? ?? '$remoteCode',
          changelog: j['changelog'] as String? ?? '常规更新',
          size: (j['size'] as num?)?.toInt() ?? 0,
          force: j['force'] == true,
          url: (j['url'] as String?)?.isNotEmpty == true
              ? j['url'] as String
              : apkUrl(host),
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

  static Future<File> download(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await _updateDir();
    final dest = File('${dir.path}/$apkName');
    if (await dest.exists()) await dest.delete();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception('下载失败：HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      var got = 0;
      final sink = dest.openWrite();
      try {
        await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
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
    final base =
        await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final dir = Directory('${base.path}/updates');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<bool> canInstallUnknown() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallUnknown') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUnknownAppSources() async {
    try {
      await _channel.invokeMethod('openUnknownAppSources');
    } catch (_) {}
  }

  static Future<void> installApk(String path) async {
    await _channel.invokeMethod('installApk', {'path': path});
  }
}
