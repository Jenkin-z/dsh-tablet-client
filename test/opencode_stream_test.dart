/// opencode SSE 传输集成测试（真起本地 HTTP 服务，不 mock 网络）
///
/// 锁死的语义：
/// - 帧以 `data:` JSON 行为单位、空行分帧；`: heartbeat` 注释行忽略；
/// - chunk 边界落在 JSON 中间 / 多字节字符中间都不能丢帧或出替换符
///   （中文打字机增量在 TCP 边界上被劈开是常态）；
/// - 半截 JSON（连接被切断的瞬间）直接丢弃，不影响后续帧；
/// - Basic 鉴权头必须是 `opencode:<password>`；
/// - 401 授权失败不重试（密码错了重试也没用）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_stream.dart';

const _password = 'test-pw';
final _expectedAuth =
    'Basic ${base64Encode(utf8.encode('opencode:$_password'))}';

/// 绕过环境代理变量直连 loopback（开发机上可能挂着 HTTP_PROXY，
/// dart:io 默认会读环境变量走代理，loopback 测试就被代理吞掉）
class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (url) => 'DIRECT';
    return client;
  }
}

Future<bool> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return true;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return cond();
}

void main() {
  HttpServer? server;
  late int port;
  final hits = <HttpRequest>[];

  setUpAll(() async {
    HttpOverrides.global = _DirectHttpOverrides();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server!.port;
    server!.listen((req) async {
      hits.add(req);
      final res = req.response;
      if (req.uri.path != '/api/event') {
        res.statusCode = 404;
        await res.close();
        return;
      }
      if (req.headers.value('authorization') != _expectedAuth) {
        res.statusCode = 401;
        await res.close();
        return;
      }
      res.statusCode = 200;
      res.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');

      // ① 半截 JSON：第一块只给一半，第二块补全
      res.add(utf8.encode('data: {"type":"session.text.delta","da'));
      await res.flush();

      res.add(utf8.encode('ta":{"sessionID":"s1","delta":"你好"}}\n\n'));
      await res.flush();

      // ② 心跳注释行：不产事件
      res.add(utf8.encode(': heartbeat\n\n'));
      await res.flush();

      // ③ CRLF 行尾 + 未知字段（id/event）忽略
      res.add(utf8.encode(
          'id: 42\r\nevent: whatever\r\n'
          'data: {"type":"session.execution.started","data":{"sessionID":"s1"}}\r\n\r\n'));
      await res.flush();

      // ④ 多字节字符被 TCP 边界劈开：「世」= E4 B8 96，前两字节单独一块
      final frameText =
          'data: {"type":"session.text.delta","data":{"sessionID":"s1","delta":"世界"}}\n\n';
      final all = utf8.encode(frameText);
      final cutAt =
          utf8.encode(frameText.substring(0, frameText.indexOf('世'))).length + 2;
      res.add(all.sublist(0, cutAt));
      await res.flush();
      res.add(all.sublist(cutAt));
      await res.flush();

      // ⑤ data: 无空格；data 非 Map / 无 type 的帧不产事件
      res.add(utf8.encode('data:{"type":"session.tool.success","data":{}}\n\n'));
      await res.flush();
      res.add(utf8.encode('data: "just-a-string"\n\n'));
      await res.flush();
      res.add(utf8.encode('data: {"data":{"x":1}}\n\n'));
      await res.flush();

      // ⑥ 半截 JSON 后直接关流：丢弃、不崩、不再产事件
      res.add(utf8.encode('data: {"type":"session.text.ended","data":{"text":"未完成'));
      await res.flush();
      await res.close();
    });
  });

  tearDownAll(() async {
    HttpOverrides.global = null;
    await server?.close(force: true);
  });

  test('SSE 帧解析：分片 / 心跳 / CRLF / 劈开的字符 / 半截 JSON', () async {
    final events = <Map<String, dynamic>>[];
    var connected = 0;
    var disconnected = 0;
    final errors = <String>[];
    final stream = OpenCodeStream(
        baseUrl: 'http://127.0.0.1:$port', password: _password)
      ..onConnected = () {
        connected++;
      }
      ..onDisconnected = () {
        disconnected++;
      }
      ..onError = errors.add
      ..onEvent = (type, data) => events.add({'type': type, ...data});
    addTearDown(stream.dispose);

    stream.connect();

    expect(
        await _waitFor(() => events.length == 4), isTrue,
        reason: '4 个事件帧应全部到达（实际 ${events.length} 个：$events）');
    expect(await _waitFor(() => connected == 1), isTrue);
    expect(errors, isEmpty);

    expect(events[0]['type'], 'session.text.delta');
    expect(events[0]['delta'], '你好');
    expect(events[1]['type'], 'session.execution.started');
    expect(events[1]['sessionID'], 's1');
    expect(events[2]['type'], 'session.text.delta');
    expect(events[2]['delta'], '世界'); // 劈开的多字节字符不能出替换符
    expect(events[3]['type'], 'session.tool.success');
    expect(events[3].keys.where((k) => k != 'type'), isEmpty);

    // 流自然结束：半截 JSON 被丢弃、不崩、不再产事件
    expect(await _waitFor(() => disconnected == 1), isTrue);
    await Future.delayed(const Duration(milliseconds: 300));
    expect(events, hasLength(4));
    expect(errors, isEmpty);
  });

  test('授权失败：401 上报错且不重试', () async {
    final errors = <String>[];
    final stream = OpenCodeStream(
        baseUrl: 'http://127.0.0.1:$port', password: 'wrong-pw')
      ..onError = errors.add;
    addTearDown(stream.dispose);

    stream.connect();

    expect(await _waitFor(() => errors.isNotEmpty), isTrue);
    expect(errors.single, contains('授权失败'));

    // 等过快速重连窗口（3s）也不应发出第二次请求
    final hitsBefore = hits.length;
    await Future.delayed(const Duration(milliseconds: 3500));
    expect(hits.length, hitsBefore, reason: '401 后不应重试');
  });
}
