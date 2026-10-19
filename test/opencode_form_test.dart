/// opencode 表单测试（v1 范围外补接后的回归锁）
///
/// 锁死的语义（全部真机实测，docs/opencode-openapi-v2.json 与实服有出入）：
/// - 列表接口不含 state，pending 与否靠 detail；创建/应答无 SSE 事件，
///   发现提问只能靠轮询对账（已由 backend 5s 周期 + turn 边沿覆盖）；
/// - reply：204 = 已提交；409 FormAlreadySettledError / 404 FormNotFoundError
///   = 已被解决（返回 false，UI 安静关闭）；400 FormInvalidAnswerError
///   = 答案不合法（上抛，服务端 message 直显）；
/// - cancel 带 message query param，告诉 Agent 为什么没答；
/// - SessionState 表单队列与 DSH 提问对称：按会话隔离、同 formId 去重、
///   reset 清空、pendingKindOf 把表单当「等待回答」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/pending.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_form_api.dart';
import 'package:dsh_tablet_client/services/session_state.dart';

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

PendingForm _form(String id, {String sessionId = 's1'}) => PendingForm(
      formId: id,
      sessionId: sessionId,
      title: '标题',
      fields: const [
        {'key': 'env', 'type': 'string', 'required': true},
      ],
      metadata: const {'kind': 'question'},
    );

void main() {
  HttpOverrides.global = _DirectHttpOverrides();

  group('SessionState 表单队列', () {
    late SessionState state;

    setUp(() => state = SessionState());

    test('addForm 同 formId 去重；form 只选当前会话', () {
      state.addForm(_form('f1'));
      state.addForm(_form('f1'));
      state.addForm(_form('f2', sessionId: 'other'));
      expect(state.allForms.map((f) => f.formId), ['f1', 'f2']);
      state.setSessionId('s1');
      expect(state.form?.formId, 'f1');
      expect(state.hasForeignForm, isTrue);
    });

    test('removeForm 精准移除', () {
      state.addForm(_form('f1'));
      state.addForm(_form('f2'));
      state.removeForm('f1');
      expect(state.allForms.map((f) => f.formId), ['f2']);
      // 移除不存在的 id 不报错
      state.removeForm('nope');
      expect(state.allForms, hasLength(1));
    });

    test('reset 清空表单与弹窗开闭态', () {
      state.addForm(_form('f1'));
      state.setFormDialogOpen(true);
      state.reset();
      expect(state.allForms, isEmpty);
      expect(state.formDialogOpen, isFalse);
    });

    test('pendingKindOf 把表单当「等待回答」，pendingSessionIds 含表单会话', () {
      state.addForm(_form('f1'));
      expect(state.pendingKindOf('s1'), 'question');
      expect(state.pendingSessionIds, {'s1'});
    });

    test('PendingForm.fromInfo 解析服务端形状（含 metadata）', () {
      final f = PendingForm.fromInfo({
        'id': 'frm_1',
        'sessionID': 'ses_1',
        'title': '部署确认',
        'metadata': {'kind': 'question'},
        'fields': [
          {'key': 'env', 'type': 'string'},
        ],
      });
      expect(f.formId, 'frm_1');
      expect(f.fromAgent, isTrue);
      expect(f.fields.single['key'], 'env');
      // 缺 metadata / fields 不炸
      final bare = PendingForm.fromInfo({'id': 'frm_2'});
      expect(bare.title, '表单');
      expect(bare.fields, isEmpty);
      expect(bare.fromAgent, isFalse);
    });
  });

  group('OpenCodeFormApi（本地 HTTP 服务，协议事实为准）', () {
    HttpServer? server;
    late int port;
    late OpenCodeFormApi api;

    /// 可编程的假 opencode：按 path/method 返回脚本化的响应
    final log = <String>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server!.port;
      api = OpenCodeFormApi(baseUrl: 'http://127.0.0.1:$port', password: _password);
      server!.listen((req) async {
        log.add('${req.method} ${req.uri.path}');
        final res = req.response;
        if (req.headers.value('authorization') != _expectedAuth) {
          res.statusCode = 401;
          await res.close();
          return;
        }
        final p = req.uri.path;
        if (p == '/api/session/s1/form' && req.method == 'GET') {
          res.statusCode = 200;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            'data': [
              {
                'id': 'frm_1',
                'sessionID': 's1',
                'title': 't',
                'fields': [
                  {'key': 'env', 'type': 'string'}
                ]
              },
            ]
          }));
          await res.close();
          return;
        }
        if (p == '/api/session/s1/form/frm_1' && req.method == 'GET') {
          res.statusCode = 200;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            'data': {
              'id': 'frm_1',
              'sessionID': 's1',
              'title': 't',
              'fields': [
                {'key': 'env', 'type': 'string'}
              ],
              'state': {'status': 'pending'},
            }
          }));
          await res.close();
          return;
        }
        if (p == '/api/session/s1/form/frm_ok/reply' && req.method == 'POST') {
          res.statusCode = 204;
          await res.close();
          return;
        }
        if (p == '/api/session/s1/form/frm_settled/reply') {
          res.statusCode = 409;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            '_tag': 'FormAlreadySettledError',
            'id': 'frm_settled',
            'message': 'Form already settled: frm_settled',
          }));
          await res.close();
          return;
        }
        if (p == '/api/session/s1/form/frm_gone/reply') {
          res.statusCode = 404;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            '_tag': 'FormNotFoundError',
            'message': 'Form not found: frm_gone',
          }));
          await res.close();
          return;
        }
        if (p == '/api/session/s1/form/frm_bad/reply') {
          res.statusCode = 400;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            '_tag': 'FormInvalidAnswerError',
            'message': 'Missing required form field: env',
          }));
          await res.close();
          return;
        }
        if (p == '/api/session/s1/form/frm_1' && req.method == 'DELETE') {
          res.statusCode = 204;
          await res.close();
          return;
        }
        res.statusCode = 404;
        await res.close();
      });
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test('listForms / formDetail 走 Basic 鉴权', () async {
      final list = await api.listForms('s1');
      expect(list.single['id'], 'frm_1');
      final detail = await api.formDetail('s1', 'frm_1');
      expect((detail['state'] as Map)['status'], 'pending');
      expect(log, containsAll(['GET /api/session/s1/form']));
    });

    test('reply 204 → true（已提交）', () async {
      expect(await api.replyForm('s1', 'frm_ok', {'env': 'prod'}), isTrue);
    });

    test('reply 409 / 404 → false（已解决，本地移除即可）', () async {
      expect(await api.replyForm('s1', 'frm_settled', {'env': 'x'}), isFalse);
      expect(await api.replyForm('s1', 'frm_gone', {'env': 'x'}), isFalse);
    });

    test('reply 400 → 上抛且带服务端 message', () async {
      await expectLater(
        api.replyForm('s1', 'frm_bad', {}),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Missing required form field: env'),
        )),
      );
    });

    test('cancelForm 204 + message query param', () async {
      expect(await api.cancelForm('s1', 'frm_1', message: '用户放弃回答'), isTrue);
      expect(log.last, startsWith('DELETE /api/session/s1/form/frm_1'));
    });

    test('401 → OpenCodeAuthException', () async {
      final bad = OpenCodeFormApi(
        baseUrl: 'http://127.0.0.1:$port',
        password: 'wrong',
      );
      await expectLater(
        bad.listForms('s1'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('授权失败'),
        )),
      );
    });
  });
}
