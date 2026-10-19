/// opencode 事件映射单测（纯函数，不碰网络与状态）
///
/// 锁死的语义：
/// - SSE 词表以真机实测为准（docs/sse-capture*.txt），改映射先改这里；
/// - messagesToChat 只产 user/assistant 气泡，reasoning/tool 块跳过
///   （与 DSH extractContentBlocks 同语义，页面两后端共用一套气泡）；
/// - normalizeSession 的 blank 语义 = 「建了没用过的空会话」，
///   只保留当前那一个是页面层 isUserFacingSession 的规则，不在这里判。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/opencode/opencode_mapper.dart';

/// 收集 mapper 回调的假 sink
class _Recorder {
  final deltas = <String>[];
  final finals = <String>[];
  final turnStarts = <String>[];
  final turnEnds = <String>[];
  final toolCalls = <Map<String, String?>>[];
  var toolResults = 0;
  final approvals = <Map<String, dynamic>>[];
  final resolved = <String>[];
  final userEchoes = <String>[];
  final created = <String>[];
  final renamed = <Map<String, String>>[];
  final formsResolved = <String>[];

  late final OpenCodeEventSink sink = OpenCodeEventSink(
    onTextDelta: deltas.add,
    onAssistantFinal: finals.add,
    onTurnStart: turnStarts.add,
    onTurnEnd: turnEnds.add,
    onToolCall: (name, args) => toolCalls.add({'name': name, 'args': args}),
    onToolResult: () => toolResults++,
    onApproval: ({
      required String sessionId,
      required String approvalId,
      required String action,
      required List<String> resources,
      String? message,
    }) =>
        approvals.add({
          'sessionId': sessionId,
          'approvalId': approvalId,
          'action': action,
          'resources': resources,
          'message': message,
        }),
    onApprovalResolved: resolved.add,
    onUserEcho: userEchoes.add,
    onSessionCreated: created.add,
    onSessionRenamed: (id, title) => renamed.add({'id': id, 'title': title}),
    onFormResolved: formsResolved.add,
  );
}

void main() {
  group('SSE 事件映射', () {
    late _Recorder rec;

    setUp(() => rec = _Recorder());

    void map(String type, Map<String, dynamic> data) =>
        OpenCodeMapper.mapEvent(type: type, data: data, sink: rec.sink);

    test('session.text.delta → 打字机增量', () {
      map('session.text.delta', {'sessionID': 's1', 'delta': '你好'});
      map('session.text.delta', {'sessionID': 's1', 'delta': '世界'});
      expect(rec.deltas, ['你好', '世界']);
    });

    test('delta 为空/缺失时不上抛', () {
      map('session.text.delta', {'sessionID': 's1', 'delta': ''});
      map('session.text.delta', {'sessionID': 's1'});
      expect(rec.deltas, isEmpty);
    });

    test('session.text.ended → 终稿', () {
      map('session.text.ended', {'sessionID': 's1', 'text': '完整回答'});
      expect(rec.finals, ['完整回答']);
      // text 缺失时给空串，由上层判空
      map('session.text.ended', {'sessionID': 's1'});
      expect(rec.finals, ['完整回答', '']);
    });

    test('execution 三态 → turn 结束', () {
      map('session.execution.started', {'sessionID': 's1'});
      expect(rec.turnStarts, ['s1']);
      for (final t in const [
        'session.execution.succeeded',
        'session.execution.interrupted',
        'session.execution.failed',
      ]) {
        map(t, {'sessionID': 's1'});
      }
      expect(rec.turnEnds, ['s1', 's1', 's1']);
    });

    test('sessionID 缺失的 execution 事件丢弃', () {
      map('session.execution.started', {});
      map('session.execution.succeeded', {});
      expect(rec.turnStarts, isEmpty);
      expect(rec.turnEnds, isEmpty);
    });

    test('tool.input.started 无参数，tool.called 带 input JSON', () {
      map('session.tool.input.started', {'sessionID': 's1', 'name': 'bash'});
      expect(rec.toolCalls.single['name'], 'bash');
      expect(rec.toolCalls.single['args'], isNull);

      map('session.tool.called', {
        'sessionID': 's1',
        'name': 'bash',
        'input': {'command': 'ls -la'},
      });
      expect(rec.toolCalls.last['name'], 'bash');
      expect(rec.toolCalls.last['args'], '{"command":"ls -la"}');

      map('session.tool.success', {'sessionID': 's1'});
      map('session.tool.failed', {'sessionID': 's1'});
      expect(rec.toolResults, 2);
    });

    test('permission.asked → 待审批（含资源列表与 message）', () {
      map('permission.asked', {
        'id': 'per_1',
        'sessionID': 's1',
        'action': 'shell',
        'resources': ['*'],
        'message': '允许执行 shell？',
      });
      final a = rec.approvals.single;
      expect(a['approvalId'], 'per_1');
      expect(a['sessionId'], 's1');
      expect(a['action'], 'shell');
      expect(a['resources'], ['*']);
      expect(a['message'], '允许执行 shell？');
    });

    test('permission.asked 缺 id 时丢弃（避免空审批项）', () {
      map('permission.asked', {'sessionID': 's1', 'action': 'shell'});
      map('permission.asked', {'id': '', 'sessionID': 's1'});
      expect(rec.approvals, isEmpty);
    });

    test('permission.replied/rejected → 按 requestID 解除', () {
      map('permission.replied', {'requestID': 'per_1'});
      map('permission.rejected', {'requestID': 'per_2'});
      expect(rec.resolved, ['per_1', 'per_2']);
      map('permission.replied', {});
      expect(rec.resolved, hasLength(2));
    });

    test('session.inbox.enqueued → 别的客户端发的用户消息', () {
      map('session.inbox.enqueued', {'sessionID': 's1', 'inboxID': 'inb_1'});
      expect(rec.userEchoes, ['inb_1']);
      map('session.inbox.enqueued', {'sessionID': 's1', 'inboxID': ''});
      expect(rec.userEchoes, hasLength(1));
    });

    test('session.created / renamed → 会话元数据', () {
      map('session.created', {'sessionID': 's9'});
      expect(rec.created, ['s9']);
      map('session.renamed', {'sessionID': 's9', 'title': '新标题'});
      expect(rec.renamed.single, {'id': 's9', 'title': '新标题'});
      // 空标题不改名
      map('session.renamed', {'sessionID': 's9', 'title': ''});
      expect(rec.renamed, hasLength(1));
    });

    test('form.cancelled → 表单解决（实测唯一有事件的表单动作）', () {
      // 真机实测：创建/应答无 SSE 事件，只有 cancelled 推 {id, sessionID}
      map('form.cancelled', {'id': 'frm_1', 'sessionID': 's1'});
      expect(rec.formsResolved, ['frm_1']);
      // 缺 id 不上抛
      map('form.cancelled', {'sessionID': 's1'});
      expect(rec.formsResolved, hasLength(1));
    });

    test('未列举的事件类型安全忽略', () {
      for (final t in const [
        'session.usage.updated',
        'session.step.updated',
        'project.updated',
        'model.updated',
        'server.connected',
      ]) {
        map(t, {'sessionID': 's1', 'whatever': 1});
      }
      expect(rec.deltas, isEmpty);
      expect(rec.turnStarts, isEmpty);
      expect(rec.approvals, isEmpty);
      expect(rec.userEchoes, isEmpty);
    });
  });

  group('messagesToChat：历史 → 气泡', () {
    test('user 顶层 text；assistant content[] 拼接（跳过 reasoning/tool）', () {
      final raw = <dynamic>[
        {
          'type': 'user',
          'id': 'm1',
          'text': '帮我查一下',
        },
        {
          'type': 'assistant',
          'id': 'm2',
          'content': [
            {'type': 'reasoning', 'text': '内部推理不应上屏'},
            {'type': 'text', 'text': '第一部'},
            {'type': 'tool', 'name': 'bash'},
            {'type': 'text', 'text': '第二部'},
          ],
        },
      ];
      final msgs = OpenCodeMapper.messagesToChat(raw);
      expect(msgs, hasLength(2));
      expect(msgs[0].role, 'user');
      expect(msgs[0].id, 'u-m1');
      expect(msgs[0].content, '帮我查一下');
      expect(msgs[1].role, 'assistant');
      expect(msgs[1].id, 'a-m2');
      expect(msgs[1].content, '第一部第二部');
      expect(msgs[1].content.contains('内部推理'), isFalse);
    });

    test('空文本 / 非 user/assistant 类型不产气泡', () {
      final raw = <dynamic>[
        {'type': 'user', 'id': 'm1', 'text': ''},
        {'type': 'assistant', 'id': 'm2', 'content': <dynamic>[]},
        {'type': 'idle', 'id': 'm3'},
        {'type': 'system', 'id': 'm4', 'text': '系统消息'},
        {'type': 'model-switched', 'id': 'm5'},
        'not-a-map',
      ];
      expect(OpenCodeMapper.messagesToChat(raw), isEmpty);
    });

    test('顺序由调用方保证（asc），mapper 不做重排', () {
      final raw = <dynamic>[
        {'type': 'user', 'id': 'm1', 'text': '一'},
        {'type': 'assistant', 'id': 'm2', 'content': [{'type': 'text', 'text': '答'}]},
      ];
      final msgs = OpenCodeMapper.messagesToChat(raw);
      expect(msgs.map((m) => m.content).toList(), ['一', '答']);
    });
  });

  group('normalizeSession：Session.Info → 归一化 map', () {
    test('title 进 projections.values，与 DSH 形状一致', () {
      final m = OpenCodeMapper.normalizeSession({
        'id': 's1',
        'title': '会话标题',
        'time': {'created': 100, 'updated': 200},
      });
      expect(m['sessionId'], 's1');
      expect(m['updatedAt'], 200);
      expect(m['running'], isFalse);
      expect(m['blank'], isFalse);
      expect(
        (m['projections'] as Map)['values'],
        {'title': '会话标题'},
      );
    });

    test('running 来自 /api/session/active 的键集合', () {
      final m = OpenCodeMapper.normalizeSession(
        {'id': 's1', 'title': 't', 'time': {'created': 100, 'updated': 200}},
        activeIds: {'s1', 's2'},
      );
      expect(m['running'], isTrue);
    });

    test('blank：建了没用过的空会话（updated <= created）', () {
      final blank = OpenCodeMapper.normalizeSession(
          {'id': 's1', 'time': {'created': 100, 'updated': 100}});
      expect(blank['blank'], isTrue);
      final used = OpenCodeMapper.normalizeSession(
          {'id': 's2', 'time': {'created': 100, 'updated': 101}});
      expect(used['blank'], isFalse);
    });

    test('缺 time / 缺 title 时安全降级', () {
      final m = OpenCodeMapper.normalizeSession({'id': 's1'});
      expect(m['updatedAt'], 0);
      expect(m['blank'], isTrue); // 0 <= 0
      expect((m['projections'] as Map)['values'], isEmpty);
    });
  });

  group('modelSelectionOf：Model.Ref → ModelSelection', () {
    test('完整 providerID + id + variant', () {
      final s = OpenCodeMapper.modelSelectionOf({
        'providerID': 'anthropic',
        'id': 'claude-sonnet-4',
        'variant': 'high',
      });
      expect(s, isNotNull);
      expect(s!.provider, 'anthropic');
      expect(s.model, 'claude-sonnet-4');
      expect(s.reasoningEffort, 'high');
    });

    test('variant=default 视为未指定档位', () {
      final s = OpenCodeMapper.modelSelectionOf({
        'providerID': 'anthropic',
        'id': 'claude-sonnet-4',
        'variant': 'default',
      });
      expect(s!.reasoningEffort, isNull);
    });

    test('非 Map / 缺字段 → null', () {
      expect(OpenCodeMapper.modelSelectionOf(null), isNull);
      expect(OpenCodeMapper.modelSelectionOf('anthropic/x'), isNull);
      expect(OpenCodeMapper.modelSelectionOf({'providerID': 'anthropic'}), isNull);
      expect(OpenCodeMapper.modelSelectionOf({'id': 'x'}), isNull);
    });
  });

  group('approvalReason：人类可读原因', () {
    test('message 优先，否则资源拼接', () {
      expect(OpenCodeMapper.approvalReason(['*'], '允许执行 shell？'), '允许执行 shell？');
      expect(OpenCodeMapper.approvalReason(['/etc', '/var'], null), '/etc、/var');
      expect(OpenCodeMapper.approvalReason([], null), isNull);
      expect(OpenCodeMapper.approvalReason([], ''), isNull);
    });
  });
}
