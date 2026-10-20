/// DSH 配对地址解析单测（NativeAuth.parse）
///
/// 锁死的语义：任意 IP / 主机名 / IPv6 / 尾斜杠 / 带路径都放行，
/// 不限定点分十进制格式；认不出的输入返回 null，不猜。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/dsh/dsh_auth.dart';

void main() {
  group('裸 host:port / 纯 host', () {
    test('标准点分 IP:端口', () {
      final t = NativeAuth.parse('192.168.10.171:3080');
      expect(t!.host, '192.168.10.171');
      expect(t.port, 3080);
      expect(t.token, isNull);
    });

    test('0.0.0.0 与非 192 网段照常解析', () {
      expect(NativeAuth.parse('0.0.0.0:3080')!.host, '0.0.0.0');
      expect(NativeAuth.parse('10.0.0.5:3080')!.host, '10.0.0.5');
      expect(NativeAuth.parse('172.16.3.4')!.host, '172.16.3.4');
    });

    test('纯 host → 默认端口 3080', () {
      final t = NativeAuth.parse('my-pc.local');
      expect(t!.host, 'my-pc.local');
      expect(t.port, 3080);
    });

    test('尾斜杠 / 带路径 → 只取 host+port', () {
      final t = NativeAuth.parse('0.0.0.0:3080/');
      expect(t!.host, '0.0.0.0');
      expect(t.port, 3080);
      expect(NativeAuth.parse('myhost:3080/x')!.host, 'myhost');
    });

    test('IPv6 裸输入', () {
      final t = NativeAuth.parse('[::1]:3080');
      expect(t!.host, '::1');
      expect(t.port, 3080);
    });
  });

  group('完整链接（含启动令牌）', () {
    test('http://IP:3080/?token=r_x → 抽出 token', () {
      final t = NativeAuth.parse('http://192.168.10.171:3080/?token=r_abc');
      expect(t!.host, '192.168.10.171');
      expect(t.port, 3080);
      expect(t.token, 'r_abc');
    });

    test('配对页链接 http://IP:8899/ → isPairServer', () {
      final t = NativeAuth.parse('http://10.0.0.5:8899/');
      expect(t!.host, '10.0.0.5');
      expect(t.port, 8899);
      expect(t.isPairServer, isTrue);
    });
  });

  group('认不出的输入', () {
    test('空 / 纯空格 → null', () {
      expect(NativeAuth.parse(''), isNull);
      expect(NativeAuth.parse('   '), isNull);
    });

    test('含空格的胡乱输入 → null', () {
      expect(NativeAuth.parse('hello world'), isNull);
    });

    test('端口不是数字 / 溢出 / 越界 → null', () {
      expect(NativeAuth.parse('my-pc:abc'), isNull);
      expect(NativeAuth.parse('my-pc:99999999999999999999'), isNull);
      expect(NativeAuth.parse('0.0.0.0:99999'), isNull);
    });

    test('非 http(s) scheme → null', () {
      expect(NativeAuth.parse('ftp://10.0.0.1'), isNull);
    });

    test('缺 host 的 URL → null', () {
      expect(NativeAuth.parse('http://'), isNull);
      expect(NativeAuth.parse('http:/x'), isNull);
    });
  });
}
