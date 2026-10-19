/// opencode 目标解析单测（授权链接 / URL / 裸 host:port）
///
/// 锁死的语义：
/// - 授权链接必须抽出 pairCode（换令牌的唯一凭据），基址只取 scheme+host+port；
/// - https 无端口默认 443，http 无端口默认 4096（opencode serve 默认口）；
/// - 裸 host:port 补 http:// 与默认端口；认不出的输入返回 null，不猜。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_target.dart';

void main() {
  group('授权链接', () {
    test('完整链接：抽出 pairCode，基址去路径', () {
      final t = parseOpenCodeTarget(
          'https://abc123.try.opencode.run/auth/connect/CODE-9f8e7d?x=1#frag');
      expect(t, isNotNull);
      expect(t!.pairCode, 'CODE-9f8e7d');
      expect(t.baseUrl, 'https://abc123.try.opencode.run');
      expect(t.host, 'abc123.try.opencode.run');
      expect(t.port, 443); // https 无显式端口
    });

    test('链接带端口', () {
      final t = parseOpenCodeTarget('http://10.0.0.1:4096/auth/connect/abc');
      expect(t!.pairCode, 'abc');
      expect(t.baseUrl, 'http://10.0.0.1:4096');
      expect(t.port, 4096);
    });

    test('普通 URL 没有授权码 → pairCode 为 null', () {
      final t = parseOpenCodeTarget('http://192.168.10.5:4096/');
      expect(t!.pairCode, isNull);
      expect(t.baseUrl, 'http://192.168.10.5:4096');
    });
  });

  group('裸 host:port', () {
    test('host:port → http 基址', () {
      final t = parseOpenCodeTarget('192.168.10.5:4096');
      expect(t!.baseUrl, 'http://192.168.10.5:4096');
      expect(t.host, '192.168.10.5');
      expect(t.port, 4096);
      expect(t.pairCode, isNull);
    });

    test('只有 host → 默认端口 4096', () {
      final t = parseOpenCodeTarget('192.168.10.5');
      expect(t!.port, 4096);
      expect(t.baseUrl, 'http://192.168.10.5');
    });

    test('端口不是数字 → 拒认（不猜）', () {
      expect(parseOpenCodeTarget('my-pc:abc'), isNull);
    });

    test('端口溢出 → 回落 4096', () {
      final t = parseOpenCodeTarget('my-pc:99999999999999999999');
      expect(t!.port, 4096);
      expect(t.host, 'my-pc');
    });
  });

  group('认不出的输入', () {
    test('空 / 纯空格 → null', () {
      expect(parseOpenCodeTarget(''), isNull);
      expect(parseOpenCodeTarget('   '), isNull);
    });

    test('缺 scheme 又不是合法 host:port → null', () {
      expect(parseOpenCodeTarget('hello world'), isNull);
      expect(parseOpenCodeTarget('http:/x'), isNull);
      expect(parseOpenCodeTarget('ftp://10.0.0.1'), isNull);
    });

    test('URL 无 host → null', () {
      expect(parseOpenCodeTarget('http://'), isNull);
      expect(parseOpenCodeTarget('http:///auth/connect/x'), isNull);
    });
  });
}
