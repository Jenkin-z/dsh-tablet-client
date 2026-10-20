/// opencode 连接状态链路集成测试（真本地 HTTP/SSE 服务 + 真 OpenCodeBackend）
///
/// 锁死的语义（线上 bug 回归）：
/// - 授权成功（REST 通）后，SSE 握手完成必须把 state.connected 置 true
///   ——曾经 OpenCodeWiring 只接了 onEvent，onConnected/onDisconnected/
///   onError 全部悬空，对话页永远显示断线；
/// - onConnected 还要触发全量对账（reconcileAll 曾是死代码）；
/// - SSE 401：connectionError 可见、connected 保持 false。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/services/agent_backend.dart';
import 'package:dsh_tablet_client/services/event_dispatcher.dart';
import 'package:dsh_tablet_client/services/opencode_backend.dart';
import 'package:dsh_tablet_client/services/server_manager.dart';
import 'package:dsh_tablet_client/services/session_state.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';
import 'package:dsh_tablet_client/services/sound_service.dart';

const _password = 'test-pw';
final _expectedAuth =
    'Basic ${base64Encode(utf8.encode('opencode:$_password'))}';

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (url) => 'DIRECT';
    return client;
  }
}

Future<bool> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return true;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return cond();
}

/// testWidgets 的 FakeAsync 区里裸 `Future.delayed` 永远不会前进
/// （假时钟只随 pump 走），真实等待必须包进 runAsync。
Future<bool> _waitReal(WidgetTester tester, bool Function() cond,
        {Duration timeout = const Duration(seconds: 10)}) async =>
    await tester.runAsync(() => _waitFor(cond, timeout: timeout)) ?? false;

/// 起一个最小 opencode 假服务：REST 端点 + 常开的 SSE 流
Future<HttpServer> _startServer({bool sseAuthFail = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    if (req.uri.path == '/api/event') {
      if (sseAuthFail || req.headers.value('authorization') != _expectedAuth) {
        res.statusCode = 401;
        await res.close();
        return;
      }
      res.statusCode = 200;
      res.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      // 保持连接：周期心跳（客户端不主动断就一直开着）
      final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        try {
          res.add(utf8.encode(': heartbeat\n\n'));
          res.flush();
        } catch (_) {}
      });
      try {
        await req.response.done;
      } catch (_) {}
      timer.cancel();
      return;
    }
    if (req.headers.value('authorization') != _expectedAuth) {
      res.statusCode = 401;
      await res.close();
      return;
    }
    switch (req.uri.path) {
      case '/api/session/s1/message':
      case '/api/permission/request':
      case '/api/session/active':
        res.statusCode = 200;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'data': []}));
        await res.close();
      case '/api/session/s1/form':
        res.statusCode = 200;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'data': []}));
        await res.close();
      case '/api/session/s1':
        res.statusCode = 200;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'data': {'id': 's1', 'title': '标题'}
        }));
        await res.close();
      default:
        res.statusCode = 404;
        await res.close();
    }
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides.global = _DirectHttpOverrides();

  BackendContext _ctx(SessionState state, EventDispatcher dispatcher,
      AgentServer server) {
    final settings = SettingsService();
    return BackendContext(
      settings: settings,
      manager: ServerManager(settings),
      state: state,
      dispatcher: dispatcher,
      server: server,
      onRefreshSessions: () async {},
    );
  }

  testWidgets('SSE 就绪 → connected=true + 连接错误清空（回归：永不置连上）',
      (tester) async {
    SoundService.debugDisable();
    final server = await tester.runAsync(_startServer);
    addTearDown(() => server?.close(force: true));
    final port = server!.port;

    final state = SessionState();
    state.setSessionId('s1');
    final dispatcher = EventDispatcher(state: state);
    final backend = OpenCodeBackend(_ctx(
      state,
      dispatcher,
      AgentServer(
        id: 'srv',
        name: 'oc',
        kind: AgentKind.opencode,
        host: '127.0.0.1',
        port: port,
        url: 'http://127.0.0.1:$port',
        token: _password,
      ),
    ));
    addTearDown(backend.dispose);

    await tester.runAsync(() => backend.open('s1'));

    expect(
      await _waitReal(tester, () => state.connected),
      isTrue,
      reason: 'SSE 握手完成后必须置 connected=true（曾经永远 false）',
    );
    expect(state.connecting, isFalse);
    expect(state.connectionError, isNull,
        reason: '连上后不应残留任何错误文案');
  });

  testWidgets('SSE 401 → 连不上 + 错误可见（授权失败要能看见原因）', (tester) async {
    SoundService.debugDisable();
    final server = await tester.runAsync(() => _startServer(sseAuthFail: true));
    addTearDown(() => server?.close(force: true));
    final port = server!.port;

    final state = SessionState();
    state.setSessionId('s1');
    final dispatcher = EventDispatcher(state: state);
    final backend = OpenCodeBackend(_ctx(
      state,
      dispatcher,
      AgentServer(
        id: 'srv',
        name: 'oc',
        kind: AgentKind.opencode,
        host: '127.0.0.1',
        port: port,
        url: 'http://127.0.0.1:$port',
        token: _password,
      ),
    ));
    addTearDown(backend.dispose);

    await tester.runAsync(() => backend.open('s1'));

    expect(
      await _waitReal(tester, () => state.connectionError != null),
      isTrue,
      reason: 'SSE 授权失败必须把原因写到 connectionError',
    );
    expect(state.connectionError, contains('授权失败'));
    expect(state.connected, isFalse);
  });
}
