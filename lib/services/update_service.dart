import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/update_manifest.dart';
import '../utils/constants.dart';

export '../models/update_manifest.dart' show UpdateInfo;

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

/// 完整性校验失败（借鉴 dsh-go fail-closed：声明了指纹就必须对上）
class UpdateVerifyException implements Exception {
  final String message;
  const UpdateVerifyException(this.message);
  @override
  String toString() => message;
}

/// 下载阶段（供 UI 展示「下载 → 校验 → 就绪」）
enum UpdateDlPhase { downloading, verifying }

/// 流式哈希的收尾容器：close() 时拿到最终 Digest
class _DigestSink implements ChunkedConversionSink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest digest) => value = digest;
  @override
  void close() {}
}

/// 更新包在 DSH 同一台 PC 的 8099（version.json 与 dsh-agent.apk）
///
/// 下载遵循 dsh-go 的事务式发布模型：
/// 先落临时文件并流式计算 SHA-256，校验通过后才原子替换正式文件；
/// 替换前把上一个已验证的包保留为 LKG（同版本可免下载重装）。
class UpdateService {
  static const int updatePort = 8099;
  static const String apkName = 'dsh-agent.apk';
  static const String partSuffix = '.part';
  static const String lastSuffix = '.last.apk';
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

  /// 本地文件是否满足声明的完整性（CAS 命中判据）。
  ///
  /// 声明了 sha256 → 逐块哈希精确比对；只声明 size → 大小一致即视为命中
  /// （老清单的弱校验，仅用于免重复下载，不用于安装前放行）。
  static Future<bool> fileMatches(
    File f, {
    String? sha256,
    int size = 0,
  }) async {
    if (!await f.exists()) return false;
    if (sha256 != null && sha256.isNotEmpty) {
      final sink = _DigestSink();
      final h = crypto.sha256.startChunkedConversion(sink);
      await for (final chunk in f.openRead()) {
        h.add(chunk);
      }
      h.close();
      return sink.value!.toString().toLowerCase() == sha256.toLowerCase();
    }
    if (size > 0) return await f.length() == size;
    return false;
  }

  /// 事务化下载：临时文件 → 流式校验 → 原子替换。
  ///
  /// - CAS 复用：正式文件已满足声明完整性（如授予安装权限后重走流程），
  ///   直接返回，不再联网。
  /// - 声明了 sha256 则校验失败即抛 [UpdateVerifyException]，绝不落正式文件。
  /// - 替换前保留旧包为 LKG（同版本重装/修复用）。
  static Future<File> download(
    String url,
    void Function(double progress) onProgress, {
    String? sha256,
    int size = 0,
    void Function(UpdateDlPhase phase)? onPhase,
  }) async {
    final dir = await _updateDir();
    final dest = File('${dir.path}/$apkName');
    if (await fileMatches(dest, sha256: sha256, size: size)) {
      onProgress(1);
      return dest;
    }
    final part = File('${dir.path}/$apkName$partSuffix');
    if (await part.exists()) await part.delete();
    final client = HttpClient()..connectionTimeout = downloadConnectTimeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(downloadRequestTimeout);
      if (resp.statusCode != 200) {
        throw Exception('下载失败：HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      var got = 0;
      final hashSink = _DigestSink();
      final h = crypto.sha256.startChunkedConversion(hashSink);
      final sink = part.openWrite();
      try {
        await for (final chunk
            in resp.timeout(downloadChunkTimeout)) {
          h.add(chunk);
          sink.add(chunk);
          got += chunk.length;
          onProgress(total > 0 ? got / total : 0);
        }
      } finally {
        await sink.close();
      }
      h.close();
      onProgress(1);
      onPhase?.call(UpdateDlPhase.verifying);
      final actualSha = hashSink.value!.toString().toLowerCase();
      if (sha256 != null && sha256.isNotEmpty &&
          actualSha != sha256.toLowerCase()) {
        await part.delete();
        throw UpdateVerifyException(
            '完整性校验失败：SHA-256 与发布指纹不一致（可能是分发目录的 apk 与 version.json 不配套），请让 PC 端重新生成后再试');
      }
      if (size > 0 && got != size) {
        await part.delete();
        throw UpdateVerifyException('完整性校验失败：收到 $got 字节，清单声明 $size 字节');
      }
      // LKG：替换前保留上一个已验证的包（同版本重装/修复）
      if (await dest.exists()) {
        try {
          final last = File('${dir.path}/$apkName$lastSuffix');
          if (await last.exists()) await last.delete();
          await dest.rename(last.path);
        } catch (_) {/* 保留失败不影响本次安装 */}
      }
      await part.rename(dest.path);
      return dest;
    } on UpdateVerifyException {
      rethrow;
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
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
