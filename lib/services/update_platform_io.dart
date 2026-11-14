import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/constants.dart';
import 'update_common.dart';

export 'update_common.dart';

/// 流式哈希的收尾容器：close() 时拿到最终 Digest
class _DigestSink implements ChunkedConversionSink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest digest) => value = digest;
  @override
  void close() {}
}

const MethodChannel _installChannel = MethodChannel('dsh.agent/update');

/// IO 平台（Android）实现：事务化下载 + APK 安装
///
/// 下载遵循 dsh-go 的事务式发布模型：
/// 先落临时文件并流式计算 SHA-256，校验通过后才原子替换正式文件；
/// 替换前把上一个已验证的包保留为 LKG（同版本可免下载重装）。
class UpdatePlatform {
  static const String apkName = 'dsh-agent.apk';
  static const String partSuffix = '.part';
  static const String lastSuffix = '.last.apk';

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
  static Future<dynamic> download(
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
        await for (final chunk in resp.timeout(downloadChunkTimeout)) {
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
      if (sha256 != null &&
          sha256.isNotEmpty &&
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
      return await _installChannel.invokeMethod<bool>('canInstallUnknown') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUnknownAppSources() async {
    try {
      await _installChannel.invokeMethod('openUnknownAppSources');
    } catch (_) {}
  }

  static Future<void> installApk(String path) async {
    await _installChannel.invokeMethod('installApk', {'path': path});
  }
}
