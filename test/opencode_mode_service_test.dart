/// OpenCodeModeService 测试：模式目录过滤 + 当前模式读取 + 切换请求体
///
/// 锁死的语义（docs/opencode-openapi-v2.json）：
/// - `GET /api/agent` 返回 `data[]`（Agent.Info：id/name/description/mode），
///   `mode: subagent` 的条目不可作为会话模式，必须在数据入口过滤；
/// - 当前模式 = `GET /api/session/{id}` 顶层的 `agent` 字段；
/// - 切换 = `POST /api/session/{id}/agent`，体 `{"agent": "<id>"}`。
library;

import 'dart:convert';

import 'package:dsh_tablet_client/services/opencode/opencode_api.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _password = 'test-pw';
final _expectedAuth =
    'Basic ${base64Encode(utf8.encode('opencode:$_password'))}';

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('OpenCodeModeService', () {
    test('fetchModes 过滤 subagent，只留可切换模式', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/api/agent') {
          return _json({
            'data': [
              {
                'id': 'build',
                'name': 'Build',
                'mode': 'primary',
                'description': '全权限构建',
              },
              {
                'id': 'plan',
                'name': 'Plan',
                'mode': 'all',
                'description': '只读规划',
              },
              {
                'id': 'general',
                'name': 'General',
                'mode': 'subagent',
                'description': '仅子代理',
              },
              {'name': '坏数据'},
            ],
          });
        }
        return http.Response('not found', 404);
      });
      final service = OpenCodeModeService(
        OpenCodeApi(baseUrl: 'http://x', password: _password, client: client),
      );

      final modes = await service.fetchModes();

      expect(requests.single.headers['Authorization'], _expectedAuth);
      expect(modes.map((m) => m.id), ['build', 'plan']);
      expect(modes[0].name, 'Build');
      expect(modes[0].description, '全权限构建');
    });

    test('currentMode 读 session 顶层 agent 字段', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/session/s1');
        return _json({'data': {'id': 's1', 'agent': 'plan', 'title': 't'}});
      });
      final service = OpenCodeModeService(
        OpenCodeApi(baseUrl: 'http://x', password: _password, client: client),
      );

      expect(await service.currentMode('s1'), 'plan');
    });

    test('select 走 POST /api/session/{id}/agent，体 {"agent": id}', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        return http.Response('', 204);
      });
      final service = OpenCodeModeService(
        OpenCodeApi(baseUrl: 'http://x', password: _password, client: client),
      );

      await service.select('s1', 'plan');

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/session/s1/agent');
      expect(jsonDecode(requests.single.body), {'agent': 'plan'});
    });
  });
}
