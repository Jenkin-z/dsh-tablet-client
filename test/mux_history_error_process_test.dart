/// 历史重载一致性 + 错误显示 + 基线解码回归测试
///
/// 锁死的语义（对齐 Web 端）：
/// - turn/end（reason.kind=error）在历史里落成 system 气泡（§14.1 durable）；
/// - assistant/message 的 interrupted 标记在历史重载后仍在（§14.7）；
/// - 用户/助手消息的多 text 块用空行连接，不丢块也不黏连；
/// - 重连基线按协议 AssistantStreamRecord 解码（text-chunks /
///   reasoning-chunks / chunk 包裹形），partial text 重连存活（§5.1）；
/// - 历史装载恢复最后一个 turn 的工具卡（过程区是 durable 的）；
/// - 会话级错误在 turn/end 之后到达也能上屏（去闸门），5 秒窗口去重。
library;

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/process_step.dart';
import 'package:dsh_tablet_client/services/dsh/mux_history.dart';
import 'package:dsh_tablet_client/services/event_dispatcher.dart';
import 'package:dsh_tablet_client/services/session_state.dart';

Map<String, dynamic> _entry(
  String type,
  int seq,
  Map<String, dynamic> data, {
  String? surfaceOp,
}) {
  return {
    'type': 'event',
    'event': {
      'type': type,
      'seq': seq,
      'time': seq,
      'data': data,
      if (surfaceOp != null) 'surfaceOp': surfaceOp,
    },
  };
}

Map<String, dynamic> _userData(String text, {int turn = 1}) {
  return {
    'id': 'message-u$turn',
    'role': 'user',
    'content': [
      {'type': 'text', 'text': text}
    ],
    'source': {'kind': 'user'},
  };
}

Map<String, dynamic> _assistantData(
  List<Map<String, dynamic>> blocks, {
  required int turn,
  int step = 1,
  bool interrupted = false,
}) {
  return {
    'turn': turn,
    'step': step,
    if (interrupted) 'interrupted': true,
    'message': {'role': 'assistant', 'content': blocks},
  };
}

void main() {
  group('parseHistory —— turn-error / interrupted / 多块 join', () {
    test('turn/end（reason.kind=error）落成 system 气泡', () {
      final out = parseHistory([
        _entry('user/message', 1, _userData('看看这个')),
        _entry('assistant/message', 2, _assistantData([
          {'type': 'text', 'text': '好的'}
        ], turn: 1)),
        _entry('turn/end', 3, {
          'turn': 1,
          'reason': {
            'kind': 'error',
            'error': {'code': 'PROVIDER', 'message': '上游 502'}
          }
        }),
      ]);
      expect(out, hasLength(3));
      expect(out[2].role, 'system');
      expect(out[2].text, '上游 502');
      expect(out[2].id, 'e3');
    });

    test('正常收尾的 turn/end 不产生气泡', () {
      final out = parseHistory([
        _entry('turn/end', 1, {
          'turn': 1,
          'reason': {'kind': 'completed'}
        }),
      ]);
      expect(out, isEmpty);
    });

    test('error 缺 message 时兜底「未知错误」（与实时路径同源）', () {
      final out = parseHistory([
        _entry('turn/end', 1, {
          'turn': 1,
          'reason': {'kind': 'error'}
        }),
      ]);
      expect(out.single.text, '未知错误');
    });

    test('interrupted 的 assistant/message 尾部带「已停止」标记', () {
      final out = parseHistory([
        _entry('user/message', 1, _userData('写个长文')),
        _entry('assistant/message', 2, _assistantData(
          [
            {'type': 'text', 'text': '写到一半'}
          ],
          turn: 1,
          interrupted: true,
        )),
      ]);
      expect(out.last.text, '写到一半$interruptedSuffix');
    });

    test('用户消息多 text 块全部保留，空行连接', () {
      final out = parseHistory([
        _entry('user/message', 1, {
          'id': 'm1',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '第一段'},
            {'type': 'text', 'text': '第二段'}
          ],
          'source': {'kind': 'user'},
        }),
      ]);
      expect(out.single.text, '第一段\n\n第二段');
    });

    test('assistant 消息多 text 块空行连接（之前黏成一段）', () {
      final out = parseHistory([
        _entry('assistant/message', 1, _assistantData([
          {'type': 'text', 'text': '结论 A'},
          {'type': 'text', 'text': '结论 B'}
        ], turn: 1)),
      ]);
      expect(out.single.text, '结论 A\n\n结论 B');
    });
  });

  group('decodeAssistantBaselineStream —— 协议 AssistantStreamRecord', () {
    test('text-chunks 紧凑记录按 texts 拼接（重连 partial text 存活）', () {
      final chunks = decodeAssistantBaselineStream([
        {'type': 'text-chunks', 'time0': 1, 'index': 0, 'dt': [], 'texts': ['hel']},
        {'type': 'text-chunks', 'time0': 2, 'index': 1, 'dt': [], 'texts': ['lo', '!']},
      ]);
      expect(chunks, hasLength(2));
      expect(chunks.map((c) => c.text).join(), 'hello!');
      expect(chunks.every((c) => !c.isReasoning), isTrue);
    });

    test('reasoning-chunks 标记为 reasoning', () {
      final chunks = decodeAssistantBaselineStream([
        {'type': 'reasoning-chunks', 'time0': 1, 'index': 0, 'dt': [], 'texts': ['想一想']},
      ]);
      expect(chunks.single.isReasoning, isTrue);
      expect(chunks.single.text, '想一想');
    });

    test('chunk 包裹形（Host 累加器原始推送）兼容 text-delta / reasoning-delta', () {
      final chunks = decodeAssistantBaselineStream([
        {
          'type': 'chunk',
          'time': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'live'}
        },
        {
          'type': 'chunk',
          'time': 2,
          'chunk': {'type': 'reasoning-delta', 'index': 1, 'text': 'think'}
        },
      ]);
      expect(chunks, hasLength(2));
      expect(chunks[0].text, 'live');
      expect(chunks[0].isReasoning, isFalse);
      expect(chunks[1].text, 'think');
      expect(chunks[1].isReasoning, isTrue);
    });

    test('旧线形 {time, chunk}（无顶层 type）按包裹记录处理', () {
      final chunks = decodeAssistantBaselineStream([
        {
          'time': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'legacy'}
        },
      ]);
      expect(chunks.single.text, 'legacy');
    });

    test('tool-call-chunks 不产生文本增量（工具由 journal 收尾，避免双计）', () {
      final chunks = decodeAssistantBaselineStream([
        {
          'type': 'tool-call-chunks',
          'time0': 1,
          'index': 2,
          'dt': [],
          'id': 'call_1',
          'name': 'read',
          'args': ['{"a"']
        },
      ]);
      expect(chunks, isEmpty);
    });

    test('按 index 排序输出（防御乱序线形）', () {
      final chunks = decodeAssistantBaselineStream([
        {'type': 'text-chunks', 'time0': 1, 'index': 1, 'dt': [], 'texts': ['B']},
        {'type': 'text-chunks', 'time0': 1, 'index': 0, 'dt': [], 'texts': ['A']},
      ]);
      expect(chunks.map((c) => c.text).join(), 'AB');
    });
  });

  group('parseHistoryProcess —— 历史工具卡合成', () {
    test('tool/call + tool/result 合成 done 条目', () {
      final out = parseHistoryProcess([
        _entry('tool/call', 1, {
          'turn': 1,
          'step': 1,
          'name': 'read',
          'arguments': '{"file_path":"/a/b.txt"}'
        }),
        _entry('tool/result', 2, {
          'turn': 1,
          'message': {
            'content': [
              {'type': 'tool-result', 'isError': false}
            ]
          },
        }),
      ]);
      expect(out, hasLength(1));
      expect(out.single.kind, ProcessEntryKind.tool);
      expect(out.single.status, ProcessEntryStatus.done);
      expect(out.single.toolName, 'read');
      expect(out.single.toolDetail, '/a/b.txt');
    });

    test('isError → failed；interrupted → stopped（优先级高于 failed）', () {
      final failed = parseHistoryProcess([
        _entry('tool/call', 1, {'turn': 1, 'name': 'bash'}),
        _entry('tool/result', 2, {
          'turn': 1,
          'message': {
            'content': [
              {'type': 'tool-result', 'isError': true}
            ]
          },
        }),
      ]);
      expect(failed.single.status, ProcessEntryStatus.failed);

      final stopped = parseHistoryProcess([
        _entry('tool/call', 1, {'turn': 1, 'name': 'bash'}),
        _entry('tool/result', 2, {
          'turn': 1,
          'error': {'code': 'interrupted', 'name': 'AbortError'}
        }),
      ]);
      expect(stopped.single.status, ProcessEntryStatus.stopped);
    });

    test('只保留最后一个 turn 的条目；进行中的保持 running', () {
      final out = parseHistoryProcess([
        _entry('tool/call', 1, {'turn': 1, 'name': 'old'}),
        _entry('tool/result', 2, {'turn': 1, 'error': {'code': 'x'}}),
        _entry('tool/call', 3, {'turn': 2, 'name': 'new', 'arguments': null}),
      ]);
      expect(out, hasLength(1));
      expect(out.single.toolName, 'new');
      expect(out.single.isRunning, isTrue);
    });
  });

  group('dispatcher —— 错误上屏去闸门 + 去重', () {
    late SessionState state;
    late EventDispatcher dispatcher;

    setUp(() {
      state = SessionState();
      dispatcher = EventDispatcher(state: state);
      state.setSessionId('s1');
    });

    tearDown(() {
      dispatcher.dispose();
      state.dispose();
    });

    test('turn/end 之后到达的错误也能上屏（去闸门）', () {
      dispatcher.onTurnStart();
      dispatcher.onUserMessage('hi', null, '1', 'm1');
      dispatcher.onTurnEnd();

      dispatcher.onSessionError('s1', '模型配额不足');
      final systemMessages =
          dispatcher.messages.where((m) => m.role == 'system').toList();
      expect(systemMessages, hasLength(1));
      expect(systemMessages.single.content, '模型配额不足');
    });

    test('5 秒窗口内相同错误只上屏一次；不同错误不受影响', () {
      dispatcher.onSessionError('s1', 'boom');
      dispatcher.onSessionError('s1', 'boom');
      expect(
          dispatcher.messages.where((m) => m.role == 'system'), hasLength(1));

      dispatcher.onSessionError('s1', 'other');
      expect(
          dispatcher.messages.where((m) => m.role == 'system'), hasLength(2));
    });

    test('非当前会话的错误走 SnackBar 降级', () {
      String? snack;
      final d = EventDispatcher(
        state: state,
        onShowSnackBar: (msg) => snack = msg,
      );
      d.onSessionError('s-other', '那边炸了');
      expect(snack, contains('那边炸了'));
      expect(d.messages.where((m) => m.role == 'system'), isEmpty);
      d.dispose();
    });
  });

  group('dispatcher —— reasoning 条目 + stopped 落定 + interrupted 标记', () {
    late SessionState state;
    late EventDispatcher dispatcher;

    setUp(() {
      state = SessionState();
      dispatcher = EventDispatcher(state: state);
      state.setSessionId('s1');
    });

    tearDown(() {
      dispatcher.dispose();
      state.dispose();
    });

    Future<void> flush() =>
        Future<void>.delayed(const Duration(milliseconds: 250));

    test('reasoning 增量经 side-channel 累积为过程条目，文本增量到来时落定',
        () async {
      dispatcher.onTurnStart();
      muxNextTextDeltaIsReasoning = true;
      dispatcher.onTextDelta('想一下');
      muxNextTextDeltaIsReasoning = true;
      dispatcher.onTextDelta('再想想');
      await flush();

      expect(dispatcher.processEntries, hasLength(1));
      expect(dispatcher.processEntries.single.kind, ProcessEntryKind.reasoning);
      expect(dispatcher.processEntries.single.text, '想一下再想想');
      expect(dispatcher.processEntries.single.isRunning, isTrue);
      expect(muxNextTextDeltaIsReasoning, isFalse);

      // 文本阶段开始：思考条目落定，文本进气泡
      dispatcher.onTextDelta('回答正文');
      await flush();
      expect(dispatcher.processEntries.single.isRunning, isFalse);
      expect(dispatcher.processEntries.single.text, '想一下再想想');
      expect(dispatcher.messages.last.role, 'assistant');
      expect(dispatcher.messages.last.content, '回答正文');
    });

    test('tool/result 的 interrupted side-channel：stopped 优先于 failed', () {
      dispatcher.onTurnStart();
      dispatcher.onToolCall('bash');
      muxToolResultWasInterrupted = true;
      dispatcher.onToolResult(false);
      expect(dispatcher.processEntries.single.status,
          ProcessEntryStatus.stopped);
      // 读后即清，不串扰下一次结果
      expect(muxToolResultWasInterrupted, isFalse);
    });

    test('interrupted 的定稿把仍在跑的工具落定为 stopped，文本带停止标记', () {
      dispatcher.onTurnStart();
      dispatcher.onToolCall('bash'); // running
      dispatcher.onAssistantFinal('', true); // 空文本 + 停止
      expect(dispatcher.processEntries.single.status,
          ProcessEntryStatus.stopped);

      dispatcher.onAssistantFinal('写到一半', true);
      final assistant =
          dispatcher.messages.lastWhere((m) => m.role == 'assistant');
      expect(assistant.content, '写到一半$interruptedSuffix');
    });

    test('新一代尝试开始：上一代 reasoning 条目退场', () async {
      dispatcher.onTurnStart();
      muxNextTextDeltaIsReasoning = true;
      dispatcher.onTextDelta('上一代思考');
      await flush();
      expect(dispatcher.processEntries, hasLength(1));

      dispatcher.onAssistantStreamStart();
      expect(
          dispatcher.processEntries
              .where((e) => e.kind == ProcessEntryKind.reasoning),
          isEmpty);
    });
  });

  group('dispatcher —— onSnapshot 恢复历史工具卡与 turn-error', () {
    late SessionState state;
    late EventDispatcher dispatcher;

    setUp(() {
      state = SessionState();
      dispatcher = EventDispatcher(state: state);
      state.setSessionId('s1');
    });

    tearDown(() {
      dispatcher.dispose();
      state.dispose();
    });

    test('历史装载恢复最后一个 turn 的工具卡，哨兵在最终回答之前', () {
      dispatcher.onSnapshot([
        _entry('user/message', 1, _userData('修一下')),
        _entry('tool/call', 2, {
          'turn': 1,
          'step': 1,
          'name': 'read',
          'arguments': '{"file_path":"/x.py"}'
        }),
        _entry('tool/result', 3, {
          'turn': 1,
          'message': {
            'content': [
              {'type': 'tool-result', 'isError': false}
            ]
          },
        }),
        _entry('assistant/message', 4, _assistantData([
          {'type': 'text', 'text': '修好了'}
        ], turn: 1)),
      ]);

      expect(dispatcher.processEntries, hasLength(1));
      expect(dispatcher.processEntries.single.status, ProcessEntryStatus.done);
      expect(dispatcher.messages.where((m) => m.role == 'steps'), hasLength(1));
      final roles = dispatcher.messages.map((m) => m.role).toList();
      expect(roles.indexOf('steps') < roles.lastIndexOf('assistant'), isTrue);
      // 最后一轮已收尾（无 running 条目）：卡呈收起态
      expect(dispatcher.processCollapsed, isTrue);
    });

    test('历史里的 turn-error 落成 system 气泡', () {
      dispatcher.onSnapshot([
        _entry('user/message', 1, _userData('跑一个')),
        _entry('turn/end', 2, {
          'turn': 1,
          'reason': {
            'kind': 'error',
            'error': {'message': '会话已过期'}
          }
        }),
      ]);
      final system = dispatcher.messages
          .where((m) => m.role == 'system')
          .toList();
      expect(system, hasLength(1));
      expect(system.single.content, '会话已过期');
    });
  });
}
