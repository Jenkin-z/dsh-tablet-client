/// AgentServer 多后端兼容回归测试
///
/// 锁死的语义：
/// - 旧数据（无 kind/url）必须无缝解释为 DSH，基址由 host:port 派生；
/// - url 是权威基址（opencode 隧道是 https 完整 URL），host/port 只作展示；
/// - 凭据按 kind 分治：DSH 用 cookie，opencode 用 token，互不通用；
/// - toJson/fromJson 往返不丢字段。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/agent_server.dart';

void main() {
  group('旧数据迁移', () {
    test('无 kind/url 的旧 JSON → DSH，基址由 host:port 派生', () {
      final s = AgentServer.fromJson({
        'id': 'pc1',
        'name': '老电脑',
        'host': '192.168.1.10',
        'port': 3080,
        'cookie': 'dsh-auth-xxx=v',
      });
      expect(s.kind, AgentKind.dsh);
      expect(s.httpUrl, 'http://192.168.1.10:3080');
      expect(s.wsUrl, 'ws://192.168.1.10:3080');
      expect(s.displayAddress, '192.168.1.10:3080');
      expect(s.isPaired, isTrue);
    });

    test('旧数据 port 缺失 → 默认 3080', () {
      final s = AgentServer.fromJson({'id': 'pc1', 'host': '10.0.0.1'});
      expect(s.port, 3080);
      expect(s.httpUrl, 'http://10.0.0.1:3080');
    });
  });

  group('opencode 条目', () {
    test('url 为权威基址，https 隧道推 wss', () {
      final s = AgentServer.fromJson({
        'id': 'oc1',
        'name': 'opencode',
        'kind': 'opencode',
        'url': 'https://tunnel.example.com/',
        'token': 'pair-token-123',
      });
      expect(s.kind, AgentKind.opencode);
      expect(s.httpUrl, 'https://tunnel.example.com/');
      expect(s.wsUrl, 'wss://tunnel.example.com/');
      expect(s.displayAddress, 'tunnel.example.com');
      expect(s.isPaired, isTrue);
    });

    test('凭据按 kind 分治：opencode 有 token 没 cookie 也算已授权', () {
      final s = AgentServer(
        id: 'oc1',
        name: 'oc',
        kind: AgentKind.opencode,
        token: 't',
      );
      expect(s.isPaired, isTrue);
      expect(s.copyWith(clearToken: true).isPaired, isFalse);
    });

    test('DSH 只认 cookie：拿着 opencode 的 token 也不算已授权', () {
      final s = AgentServer(
        id: 'pc1',
        name: 'pc',
        kind: AgentKind.dsh,
        token: 't',
      );
      expect(s.isPaired, isFalse);
    });

    test('unpaired 一律覆盖为未授权', () {
      final s = AgentServer(
        id: 'pc1',
        name: 'pc',
        kind: AgentKind.dsh,
        cookie: 'c',
        unpaired: true,
      );
      expect(s.isPaired, isFalse);
    });
  });

  group('序列化往返', () {
    test('toJson/fromJson 保留 kind/url/token', () {
      const s = AgentServer(
        id: 'oc1',
        name: 'opencode',
        kind: AgentKind.opencode,
        url: 'http://127.0.0.1:4096',
        token: 'tok',
      );
      final back = AgentServer.fromJson(s.toJson());
      expect(back.kind, AgentKind.opencode);
      expect(back.url, 'http://127.0.0.1:4096');
      expect(back.token, 'tok');
      expect(back.httpUrl, s.httpUrl);
    });

    test('toJson 不写空 cookie/token/url', () {
      const s = AgentServer(
        id: 'pc1',
        name: 'pc',
        kind: AgentKind.dsh,
        host: '10.0.0.1',
      );
      final j = s.toJson();
      expect(j.containsKey('cookie'), isFalse);
      expect(j.containsKey('token'), isFalse);
      expect(j.containsKey('url'), isFalse);
      expect(j['kind'], 'dsh');
    });
  });
}
