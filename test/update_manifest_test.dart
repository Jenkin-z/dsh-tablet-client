/// 更新清单契约测试（借鉴 dsh-go Release Descriptor V2 的 fail-closed 语义）
///
/// 锁定三条：
/// 1. 声明了 sha256 就必须是合法 64 位十六进制，否则整个清单判无效；
/// 2. versionCode 是比较基准，缺失/非正数判无效；
/// 3. 老清单（无 sha256/size）向后兼容，指纹短码取前 12 位。
library;

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/update_manifest.dart';
import 'package:dsh_tablet_client/services/update_service.dart';

String sha256Hex(String s) => crypto.sha256.convert(s.codeUnits).toString();

void main() {
  group('UpdateManifest.tryParse 契约', () {
    test('完整清单正常解析，sha256 统一小写', () {
      final m = UpdateManifest.tryParse({
        'versionCode': 29,
        'versionName': '1.5.2',
        'size': 52500000,
        'changelog': '修复若干问题',
        'sha256': 'A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F90',
      });
      expect(m, isNotNull);
      expect(m!.versionCode, 29);
      expect(m.versionName, '1.5.2');
      expect(m.size, 52500000);
      expect(m.sha256, 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90');
      expect(m.integrityDeclared, isTrue);
      expect(m.fingerprintShort, 'a1b2c3d4e5f6');
    });

    test('缺 versionCode / versionCode 非正数 → 判无效', () {
      expect(UpdateManifest.tryParse({'versionName': '1.5.2'}), isNull);
      expect(UpdateManifest.tryParse({'versionCode': 0}), isNull);
      expect(UpdateManifest.tryParse({'versionCode': -3}), isNull);
    });

    test('声明了 sha256 但不合法 → fail-closed 判无效', () {
      expect(
        UpdateManifest.tryParse({
          'versionCode': 30,
          'sha256': 'abc123', // 长度不够
        }),
        isNull,
      );
      expect(
        UpdateManifest.tryParse({
          'versionCode': 30,
          'sha256': 'z' * 64, // 非十六进制
        }),
        isNull,
      );
    });

    test('size 为负数 → 判无效', () {
      expect(UpdateManifest.tryParse({'versionCode': 30, 'size': -1}), isNull);
    });

    test('老清单（无 sha256/size）向后兼容', () {
      final m = UpdateManifest.tryParse({'versionCode': 28});
      expect(m, isNotNull);
      expect(m!.sha256, isNull);
      expect(m.size, 0);
      expect(m.integrityDeclared, isFalse);
      expect(m.fingerprintShort, isNull);
    });
  });

  group('UpdateInfo 展示字段', () {
    test('sizeText 与指纹短码', () {
      final withSha = UpdateInfo(
        versionCode: 30,
        versionName: '1.6.0',
        changelog: 'x',
        size: 52500000,
        force: false,
        url: 'http://h:8099/dsh-agent.apk',
        sha256: 'abcdef123456${'0' * 52}',
      );
      expect(withSha.sizeText, '50.1 MB');
      expect(withSha.fingerprintShort, 'abcdef123456');

      final noSha = UpdateInfo(
        versionCode: 30,
        versionName: '1.6.0',
        changelog: 'x',
        size: 0,
        force: false,
        url: 'http://h:8099/dsh-agent.apk',
      );
      expect(noSha.sizeText, '未知大小');
      expect(noSha.fingerprintShort, isNull);
    });
  });

  group('UpdateService.fileMatches（CAS 命中判据）', () {
    late Directory tmp;
    const content = 'dsh-agent-apk-bytes-for-test';

    setUp(() => tmp = Directory.systemTemp.createTempSync('upd_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('sha256 精确匹配 → 命中；不匹配 → 未命中', () async {
      final f = File('${tmp.path}/a.apk')..writeAsStringSync(content);
      final sha = sha256Hex(content);
      expect(
        await UpdateService.fileMatches(f, sha256: sha),
        isTrue,
      );
      expect(
        await UpdateService.fileMatches(f, sha256: '0' * 64),
        isFalse,
      );
      // 大小写不敏感
      expect(
        await UpdateService.fileMatches(f, sha256: sha.toUpperCase()),
        isTrue,
      );
    });

    test('只声明 size：大小一致命中，不一致未命中', () async {
      final f = File('${tmp.path}/b.apk')..writeAsStringSync(content);
      expect(
        await UpdateService.fileMatches(f, size: content.length),
        isTrue,
      );
      expect(await UpdateService.fileMatches(f, size: content.length + 1), isFalse);
    });

    test('无声明、文件不存在 → 未命中', () async {
      expect(
        await UpdateService.fileMatches(File('${tmp.path}/none.apk'),
            sha256: 'a' * 64),
        isFalse,
      );
      final f = File('${tmp.path}/c.apk')..writeAsStringSync(content);
      expect(await UpdateService.fileMatches(f), isFalse);
    });
  });
}
