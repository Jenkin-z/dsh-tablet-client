/// opencode 历史窗口 + 全局事件流过滤的回归测试
///
/// 锁死的语义：
/// - `recentMessages` 走 `order=desc` 取**最新**一页再翻成升序
///   （asc 是从会话开头取，长会话下平板会永远停在旧消息上）；
/// - 全局 `/api/event` 带着别的会话的内容，按会话过滤掉。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_api.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_mapper.dart';

/// 记录 sink 收到的各类动作
class _Recorder {
  final deltas = <String>[];
  final finals = <String>[];
  final toolCalls = <String>[];
  final userEchoes = <String>[];

  late final OpenCodeEventSink sink = OpenCodeEventSink(
    onTextDelta: deltas.add,
    onAssistantFinal: finals.add,
    onTurnStart: (_) {},
    onTurnEnd: (_) {},
    onToolCall: (name, args) => toolCalls.add(name),
    onToolResult: () {},
    onApproval: ({
      required String sessionId,
      required String approvalId,
      required String action,
      required List<String> resources,
      String? message,
    }) {},
    onApprovalResolved: (_) {},
    onUserEcho: userEchoes.add,
    onSessionCreated: (_) {},
    onSessionRenamed: (String sid, String title) {},
    onFormResolved: (_) {},
  );
}

void main() {
  group('recentMessages：取最新一页', () {
    test('用 order=desc 请求，并翻成时间升序返回', () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        // 服务端按 desc 返回：最新在前
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'm3', 'type': 'assistant'},
              {'id': 'm2', 'type': 'user'},
              {'id': 'm1', 'type': 'user'},
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = OpenCodeApi(baseUrl: 'http://x', client: client);

      final msgs = await api.recentMessages('s1', limit: 50);

      expect(seen!.queryParameters['order'], 'desc');
      expect(seen!.queryParameters['limit'], '50');
      // 返回给渲染层的是升序：最早 → 最新
      expect(msgs.map((m) => m['id']).toList(), ['m1', 'm2', 'm3']);
    });
  });

  group('全局事件流按会话过滤', () {
    late _Recorder rec;

    setUp(() => rec = _Recorder());

    void map(String type, Map<String, dynamic> data) => OpenCodeMapper.mapEvent(
          type: type,
          data: data,
          sink: rec.sink,
          isCurrent: (sid) => sid == 's1',
        );

    test('别的会话的文本事件被丢掉', () {
      map('session.text.delta', {'sessionID': 's2', 'delta': '别的会话'});
      map('session.text.ended', {'sessionID': 's2', 'text': '别的会话终稿'});
      expect(rec.deltas, isEmpty);
      expect(rec.finals, isEmpty);
    });

    test('当前会话的文本事件照常', () {
      map('session.text.delta', {'sessionID': 's1', 'delta': '本会话'});
      map('session.text.ended', {'sessionID': 's1', 'text': '本会话终稿'});
      expect(rec.deltas, ['本会话']);
      expect(rec.finals, ['本会话终稿']);
    });

    test('别的会话的工具事件被丢掉', () {
      map('session.tool.called', {'sessionID': 's2', 'name': 'bash'});
      expect(rec.toolCalls, isEmpty);
    });

    test('别的会话的用户消息回声被丢掉', () {
      map('session.inbox.enqueued', {'sessionID': 's2', 'inboxID': 'm2'});
      expect(rec.userEchoes, isEmpty);
    });

    test('不传 isCurrent 时行为不变（老调用方不受影响）', () {
      OpenCodeMapper.mapEvent(
        type: 'session.text.delta',
        data: {'sessionID': 's2', 'delta': '照收'},
        sink: rec.sink,
      );
      expect(rec.deltas, ['照收']);
    });
  });
}
