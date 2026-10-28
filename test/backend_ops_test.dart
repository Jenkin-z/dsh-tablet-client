/// BackendOps 测试：设置页的免连接操作走 AgentBackend 转接层
///
/// 锁死的语义：
/// - testConnection / createSession 都经临时装配的 backend（共享工厂），
///   不直连具体 API 类；无选中后端时 testConnection=false / createSession=''；
/// - HTTP 用本机回环真实现（HttpOverrides DIRECT + HttpServer 假后端），
///   与 opencode_connect_state_test 同一风格。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/services/backend_ops.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (url) => 'DIRECT';
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _DirectHttpOverrides();

  late HttpServer server;
  late Uri base;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((req) async {
      await req.drain<void>();
      if (req.uri.path == '/api/session' && req.method == 'GET') {
        // 会话列表（testConnection 走 listSessions(limit:1)）
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': [
            {'id': 'ses_1', 'title': 't'},
          ],
        }));
        await req.response.close();
      } else if (req.uri.path == '/api/session' && req.method == 'POST') {
        // 新建会话：信封 data 是单对象
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {'id': 'ses_new', 'title': 't'},
        }));
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Future<BackendOps> _ops(AgentServer srv) async {
    final s = SettingsService();
    await s.init();
    await s.upsertServer(srv);
    await s.setActiveServer(srv.id);
    return BackendOps(s);
  }

  test('opencode 免连接操作走 backend：testConnection + createSession', () async {
    final ops = await _ops(AgentServer(
      id: 'oc1',
      name: 'oc',
      kind: AgentKind.opencode,
      url: base.toString(),
      token: 'pw',
    ));

    expect(await ops.testConnection(), isTrue);
    expect(await ops.createSession(), 'ses_new');
  });

  test('不可达后端：testConnection=false、createSession 上抛（页面负责兜底）',
      () async {
    // settings 无保存服务器时会种一台默认 DSH（active 永不为 null），
    // 所以这里的语义是「指向不可达地址」而非「无后端」
    final ops = await _ops(AgentServer(
      id: 'dead',
      name: 'dead',
      kind: AgentKind.opencode,
      url: 'http://127.0.0.1:1',
      token: 'pw',
    ));

    expect(await ops.testConnection(), isFalse);
    expect(
      () => ops.createSession(),
      throwsA(isA<Exception>()),
    );
  });
}
