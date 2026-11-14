/// 队列管理（session/updateQueue）与 prompt mode 透传的线上信封测试
///
/// 用真实回环 HTTP 桩锁定**发出的请求体**（而非源码形状）：
/// - updateQueue 三种 action 的 wire 形状（steer / remove / edit）；
/// - session/prompt 的 mode 透传：默认恒为 'queue'（发送纪律见
///   docs/design/turn-state-v4.md），'steer' 仅作为保留能力。
///
/// 协议依据：DSH_REMOTE_STREAM_MUX_PROTOCOL.md L2075
/// `{ request: { sessionId, itemId, action } }` → `{ accepted: true }`；
/// action 按 kind 判别：edit/remove 形状见 dsh_api_extras.dart 历史注释，
/// steer 依据 docs/DSH_WEB_ANALYSIS.md:43「action: edit|remove|steer」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/dsh/dsh_api.dart';

/// 回环 HTTP 桩：捕获最后一个 RPC 信封，回 `{accepted:true}`
class _RpcSpy {
  final HttpServer _server;
  Map<String, dynamic> last = {};

  _RpcSpy._(this._server);

  static Future<_RpcSpy> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _RpcSpy._(server).._listen();
  }

  void _listen() {
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) last = decoded;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"result":{"ok":true,"value":{"accepted":true}}}');
      await req.response.close();
    });
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _RpcSpy spy;
  late DshApi api;

  setUp(() async {
    spy = await _RpcSpy.start();
    api = DshApi(baseUrl: spy.baseUrl, cookie: 'dsh-auth-test=1');
  });

  tearDown(() async {
    await spy.stop();
  });

  /// 信封外层：{type, rpcId, method, payload:{args}}
  Map<String, dynamic> argsOf() =>
      (spy.last['payload'] as Map<String, dynamic>)['args']
          as Map<String, dynamic>;

  group('session/updateQueue 三种 action 的请求信封', () {
    test('steer：{sessionId, itemId, action:{kind:steer}}', () async {
      final ok = await api.steerQueuedItem('s1', 'q1');
      expect(ok, isTrue, reason: '桩回 {accepted:true}');
      expect(spy.last['type'], 'client-request');
      expect(spy.last['method'], 'session/updateQueue');
      expect(argsOf()['request'], {
        'sessionId': 's1',
        'itemId': 'q1',
        'action': {'kind': 'steer'},
      });
    });

    test('remove：{sessionId, itemId, action:{kind:remove}}', () async {
      await api.removeQueuedItem('s1', 'q2');
      expect(spy.last['method'], 'session/updateQueue');
      expect(argsOf()['request'], {
        'sessionId': 's1',
        'itemId': 'q2',
        'action': {'kind': 'remove'},
      });
    });

    test('edit：content 按协议 PromptContentPart 数组下线', () async {
      await api.editQueuedItem('s1', 'q3', '改后的内容');
      expect(spy.last['method'], 'session/updateQueue');
      expect(argsOf()['request'], {
        'sessionId': 's1',
        'itemId': 'q3',
        'action': {
          'kind': 'edit',
          'content': [
            {'type': 'text', 'text': '改后的内容'},
          ],
        },
      });
    });
  });

  group('session/prompt mode 透传', () {
    test('默认恒为 queue（发送纪律：忙闲由 Host 排队裁决）', () async {
      await api.sendPrompt('s1', 'hi', requestId: 'r1');
      final request = argsOf()['request'] as Map<String, dynamic>;
      expect(request['mode'], 'queue');
      expect(request['requestId'], 'r1');
    });

    test('显式 steer 只影响线上 mode，其余形状不变', () async {
      await api.sendPrompt('s1', 'hi', requestId: 'r2', mode: 'steer');
      final request = argsOf()['request'] as Map<String, dynamic>;
      expect(request['mode'], 'steer');
      expect(request['sessionId'], 's1');
      expect(request['content'], [
        {'type': 'text', 'text': 'hi'},
      ]);
    });
  });
}
