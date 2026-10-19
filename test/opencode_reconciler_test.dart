/// opencode 对账族集成测试（本地 HTTP 服务 + 真 SessionState/Dispatcher）
///
/// 锁死的语义：
/// - 列表不含 state：pending 与否靠 detail（N+1，单个 detail 失败跳过）；
/// - 发现 pending → dispatcher.onForm → 状态中枢入队（不重复响铃）；
/// - 服务端从 pending 变 answered/cancelled → onFormResolved 移除；
/// - 只核实当前绑定会话——其它会话的待办无法用本接口确认，不错杀；
/// - 接口整体失败（401/网络）→ 不增删（宁可漏，不可错杀）。
///
/// 真实 socket I/O 必须包在 `tester.runAsync` 里（TestWidgetsFlutterBinding
/// 默认把 HttpClient 拦成 400），dispatcher.onForm 又会触发 SoundService 的
/// 平台通道——所以用 testWidgets + runAsync 的组合，两者兼得。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/models/pending.dart';
import 'package:dsh_tablet_client/services/agent_backend.dart';
import 'package:dsh_tablet_client/services/event_dispatcher.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_api.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_form_api.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_reconciler.dart';
import 'package:dsh_tablet_client/services/server_manager.dart';
import 'package:dsh_tablet_client/services/session_state.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';
import 'package:dsh_tablet_client/services/sound_service.dart';

const _password = 'test-pw';

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

  HttpServer? server;
  late int port;
  late SessionState state;
  late EventDispatcher dispatcher;
  late BackendContext ctx;

  /// formID → detail 的 status；缺省视为 pending
  final states = <String, String>{};

  /// 强制 list 接口失败（模拟 401/网络错）
  var failList = false;

  setUp(() async {
    // audioplayers 构造后内部异步 init 会抛 MissingPluginException（fire-
    // and-forget，无法从外部捕获），测试里先彻底禁用提示音
    SoundService.debugDisable();
    states.clear();
    failList = false;
    HttpOverrides.global = _DirectHttpOverrides();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server!.port;
    server!.listen((req) async {
      final res = req.response;
      final segs = req.uri.pathSegments;
      // /api/session/s1/form（列表）与 /api/session/s1/form/{id}（详情）
      if (segs.length < 4 || segs[0] != 'api' || segs[3] != 'form') {
        res.statusCode = 404;
        await res.close();
        return;
      }
      if (failList) {
        res.statusCode = 401;
        await res.close();
        return;
      }
      if (req.method == 'GET' && segs.length == 4) {
        res.statusCode = 200;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'data': [
            for (final id in ['frm_a', 'frm_b', 'frm_broken'])
              {
                'id': id,
                'sessionID': 's1',
                'title': '标题-$id',
                'fields': [
                  {'key': 'env', 'type': 'string', 'required': true}
                ],
              }
          ]
        }));
        await res.close();
        return;
      }
      final fid = segs.last;
      if (fid == 'frm_broken') {
        res.statusCode = 404;
        await res.close();
        return;
      }
      res.statusCode = 200;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'data': {
          'id': fid,
          'sessionID': 's1',
          'title': '标题-$fid',
          'fields': [
            {'key': 'env', 'type': 'string', 'required': true}
          ],
          'state': {'status': states[fid] ?? 'pending'},
        }
      }));
      await res.close();
    });

    final settings = SettingsService();
    state = SessionState();
    state.setSessionId('s1');
    dispatcher = EventDispatcher(state: state);
    ctx = BackendContext(
      settings: settings,
      manager: ServerManager(settings),
      state: state,
      dispatcher: dispatcher,
      server: AgentServer(
        id: 'srv',
        name: 'oc',
        kind: AgentKind.opencode,
        host: '127.0.0.1',
        port: port,
        url: 'http://127.0.0.1:$port',
        token: _password,
      ),
      onRefreshSessions: () async {},
    );
  });

  tearDown(() async {
    await server?.close(force: true);
  });

  OpenCodeReconciler _reconciler() => OpenCodeReconciler(
        OpenCodeApi(baseUrl: 'http://127.0.0.1:$port', password: _password),
        OpenCodeFormApi(baseUrl: 'http://127.0.0.1:$port', password: _password),
        ctx,
        () => 's1',
      );

  /// 真实网络 I/O 必须包在 tester.runAsync 里（逃出 binding 的 HTTP 拦截）
  Future<void> _run(
    WidgetTester tester,
    Future<void> Function() body,
  ) =>
      tester.runAsync(body);

  testWidgets('pending form → 入队；answered → 不入队', (tester) async {
    states['frm_b'] = 'answered';
    await _run(tester, _reconciler().reconcileForms);
    expect(state.allForms.map((f) => f.formId), ['frm_a']);
    expect(state.form?.title, '标题-frm_a');
  });

  testWidgets('重复对账不重复入队（幂等）', (tester) async {
    // frm_broken 的 detail 404 跳过；frm_a/frm_b 都 pending → 2 个
    final r = _reconciler();
    await _run(tester, r.reconcileForms);
    await _run(tester, r.reconcileForms);
    expect(state.allForms, hasLength(2));
  });

  testWidgets('服务端从 pending → answered：对账移除', (tester) async {
    final r = _reconciler();
    await _run(tester, r.reconcileForms);
    expect(state.allForms, hasLength(2));
    states['frm_a'] = 'answered';
    states['frm_b'] = 'answered';
    await _run(tester, r.reconcileForms);
    expect(state.allForms, isEmpty);
  });

  testWidgets('单个 detail 失败（404）→ 跳过该 form，其余照常入队', (tester) async {
    // frm_broken 的 detail 返 404：跳过它，frm_a/frm_b 不受影响
    states['frm_b'] = 'answered';
    await _run(tester, _reconciler().reconcileForms);
    expect(state.allForms.map((f) => f.formId), ['frm_a']);
  });

  testWidgets('其它会话的待办不错杀（只清理 boundSessionId 的）', (tester) async {
    state.addForm(const PendingForm(
      formId: 'frm_foreign',
      sessionId: 'other-session',
      title: '外来',
      fields: [],
    ));
    states['frm_b'] = 'answered';
    await _run(tester, _reconciler().reconcileForms);
    // 当前会话的入队；外来会话的原样保留
    expect(
      state.allForms.map((f) => f.formId).toSet(),
      {'frm_a', 'frm_foreign'},
    );
  });

  testWidgets('列表接口失败（401）→ 不增删', (tester) async {
    state.addForm(const PendingForm(
      formId: 'frm_keep',
      sessionId: 's1',
      title: '保留',
      fields: [],
    ));
    failList = true;
    await _run(tester, _reconciler().reconcileForms);
    expect(state.allForms.map((f) => f.formId), ['frm_keep']);
  });
}
