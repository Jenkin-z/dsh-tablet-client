/// 协议解析回归测试
///
/// 这些用例锁定的是**曾经写错、且表面上不报错**的线形：
/// 把真实报文喂进来，防止再次悄悄回归。
///
/// 报文取自 DSH 源码 / 测试（见 docs/MUX_PROTOCOL.md 的证据表）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/pending.dart';
import 'package:dsh_tablet_client/services/dsh/mux_history.dart';
import 'package:dsh_tablet_client/utils/session_format.dart';

void main() {
  group('parseDiffView —— diff 的真实来源', () {
    // 真实报文形状：tool/result.data.meta.diffs
    final toolResult = <String, dynamic>{
      'turn': 1,
      'step': 1,
      'message': {
        'id': 'message-2',
        'role': 'user',
        'content': [
          {'type': 'tool-result', 'callId': 'call_abc', 'content': [], 'isError': false}
        ],
        'source': {'kind': 'tool', 'callId': 'call_abc', 'name': 'edit'},
      },
      'meta': {
        'diffs': [
          {
            'path': r'D:\work\a.txt',
            'oldText': 'before\n',
            'newText': 'after\n',
          }
        ]
      },
    };

    test('从 tool/result.data.meta.diffs 解析出 diff', () {
      final rec = parseDiffView(eventType: 'tool/result', data: toolResult);
      expect(rec, isNotNull);
      expect(rec!.diffs, hasLength(1));
      expect(rec.diffs.first['path'], r'D:\work\a.txt');
      expect(rec.diffs.first['oldText'], 'before\n');
      expect(rec.diffs.first['newText'], 'after\n');
      expect(rec.callId, 'call_abc');
      // 单文件时标题用文件名，比工具名更好读
      expect(rec.title, 'a.txt');
    });

    test('oldText 为 null 表示整文件新建，要保留 null 而不是空串', () {
      final rec = parseDiffView(eventType: 'tool/result', data: {
        'turn': 1,
        'message': {'source': {'callId': 'c', 'name': 'write'}},
        'meta': {
          'diffs': [
            {'path': 'new.txt', 'oldText': null, 'newText': 'hi'}
          ]
        },
      });
      expect(rec, isNotNull);
      expect(rec!.diffs.first['oldText'], isNull);
    });

    test('多文件时标题给出文件数', () {
      final rec = parseDiffView(eventType: 'tool/result', data: {
        'turn': 1,
        'message': {'source': {'callId': 'c', 'name': 'edit'}},
        'meta': {
          'diffs': [
            {'path': 'a.txt', 'oldText': 'x', 'newText': 'y'},
            {'path': 'b.txt', 'oldText': 'x', 'newText': 'y'},
          ]
        },
      });
      expect(rec!.title, '2 个文件');
    });

    test('非 tool/result 事件不产生 diff', () {
      expect(parseDiffView(eventType: 'tool/call', data: toolResult), isNull);
      expect(parseDiffView(eventType: 'user/message', data: toolResult), isNull);
    });

    test('没有 meta.diffs 时返回 null（不再依赖不存在的 view 字段）', () {
      expect(
        parseDiffView(eventType: 'tool/result', data: {
          'turn': 1,
          'message': {'source': {'name': 'bash'}},
        }),
        isNull,
      );
    });
  });

  group('extractToolDetail —— 参数是未解析的 JSON 字符串', () {
    test('优先取 command', () {
      expect(
        extractToolDetail('{"command":"npm test","description":"x"}'),
        'npm test',
      );
    });

    test('取 file_path / path', () {
      expect(
        extractToolDetail(r'{"file_path":"D:\\work\\a.txt"}'),
        r'D:\work\a.txt',
      );
    });

    test('非法 JSON 退化为截断原文，不抛异常', () {
      expect(extractToolDetail('not json at all'), 'not json at all');
      expect(extractToolDetail(null), isNull);
      expect(extractToolDetail(''), isNull);
    });

    test('多行命令压平为一行', () {
      expect(extractToolDetail('{"command":"a\\n  b"}'), 'a b');
    });
  });

  group('toolResultFailed', () {
    test('message.content[].isError 为真时算失败', () {
      expect(
        toolResultFailed({
          'message': {
            'content': [
              {'type': 'tool-result', 'isError': true}
            ]
          }
        }),
        isTrue,
      );
    });

    test('顶层 error 存在时算失败', () {
      expect(toolResultFailed({'error': {'code': 'x'}}), isTrue);
    });

    test('正常结果不算失败', () {
      expect(
        toolResultFailed({
          'message': {
            'content': [
              {'type': 'tool-result', 'isError': false}
            ]
          }
        }),
        isFalse,
      );
    });
  });

  group('projections 标题', () {
    test('读 values.title（session-title 合并进 SessionProjectionMap）', () {
      expect(
        extractProjectionTitle({
          'asOfSeq': 12,
          'values': {'title': '修一个 bug'}
        }),
        '修一个 bug',
      );
    });

    test('title 为 null 时返回 null', () {
      expect(extractProjectionTitle({'values': {'title': null}}), isNull);
    });

    test('结构缺失时不抛异常', () {
      expect(extractProjectionTitle({}), isNull);
    });
  });

  group('PendingQuestion —— plan-review 识别', () {
    test('单问 + intent.kind=plan-review + detail 才算 plan-review', () {
      final q = PendingQuestion(
        rpcId: 'e1',
        sessionId: 's1',
        questions: [
          {
            'id': 'q1',
            'question': '执行计划？',
            'detail': '## 计划',
            'options': [
              {'label': '执行'},
              {'label': '继续规划'},
            ],
            'intent': {'kind': 'plan-review', 'approve': '执行'},
          }
        ],
      );
      expect(q.isPlanReview, isTrue);
      expect(q.approveLabel, '执行');
    });

    test('缺 detail 不算 plan-review', () {
      final q = PendingQuestion(
        rpcId: 'e1',
        sessionId: 's1',
        questions: [
          {
            'id': 'q1',
            'question': 'x',
            'intent': {'kind': 'plan-review', 'approve': '执行'},
          }
        ],
      );
      expect(q.isPlanReview, isFalse);
      expect(q.approveLabel, isNull);
    });

    test('多问不算 plan-review（Web 端要求恰好 1 问）', () {
      final q = PendingQuestion(
        rpcId: 'e1',
        sessionId: 's1',
        questions: [
          {'id': 'q1', 'detail': 'd', 'intent': {'kind': 'plan-review', 'approve': 'a'}},
          {'id': 'q2', 'detail': 'd', 'intent': {'kind': 'plan-review', 'approve': 'a'}},
        ],
      );
      expect(q.isPlanReview, isFalse);
    });

    test('普通提问不是 plan-review', () {
      final q = PendingQuestion(
        rpcId: 'e1',
        sessionId: 's1',
        questions: [
          {'id': 'q1', 'question': '选哪个？'}
        ],
      );
      expect(q.isPlanReview, isFalse);
    });
  });

  group('parseHistory —— records 与实时 event 同构', () {
    test('解析 user/assistant 消息，id 带 seq 前缀', () {
      final out = parseHistory([
        {
          'type': 'event',
          'event': {
            'type': 'user/message',
            'seq': 4,
            'time': 1,
            'data': {
              'id': 'message-1',
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'hello'}
              ],
              'source': {'kind': 'user'}
            }
          }
        },
        {
          'type': 'event',
          'event': {
            'type': 'assistant/message',
            'seq': 5,
            'time': 2,
            'data': {
              'turn': 1,
              'step': 1,
              'message': {
                'role': 'assistant',
                'content': [
                  {'type': 'text', 'text': 'hi there'}
                ]
              },
              'stream': []
            }
          }
        },
      ]);
      expect(out, hasLength(2));
      expect(out[0].role, 'user');
      expect(out[0].text, 'hello');
      expect(out[0].id, 'u4');
      expect(out[1].role, 'assistant');
      expect(out[1].text, 'hi there');
      expect(out[1].id, 'a5');
    });

    test('忽略无 data 的事件', () {
      final out = parseHistory([
        {'type': 'event', 'event': {'type': 'turn/end', 'seq': 9}}
      ]);
      expect(out, isEmpty);
    });

    test('注入上下文、system 消息与 replacement surface 不上屏', () {
      final out = parseHistory([
        {
          'type': 'event',
          'event': {
            'type': 'user/message',
            'seq': 1,
            'data': {
              'id': 'ctx-1',
              'content': [
                {'type': 'text', 'text': 'runtime context'}
              ],
              'source': {'kind': 'runtime-context'},
            },
          },
        },
        {
          'type': 'event',
          'event': {
            'type': 'system/message',
            'seq': 2,
            'data': {
              'content': [
                {'type': 'text', 'text': 'system prompt'}
              ],
            },
          },
        },
        {
          'type': 'event',
          'event': {
            'type': 'user/message',
            'seq': 3,
            'surfaceOp': 'replacement',
            'data': {
              'id': 'ctx-2',
              'content': [
                {'type': 'text', 'text': 'model-facing replacement'}
              ],
              'source': {'kind': 'user'},
            },
          },
        },
        {
          'type': 'event',
          'event': {
            'type': 'user/message',
            'seq': 4,
            'data': {
              'id': 'message-1',
              'content': [
                {'type': 'text', 'text': '真人输入'}
              ],
              'source': {'kind': 'user'},
            },
          },
        },
      ]);
      expect(out, hasLength(1));
      expect(out.single.role, 'user');
      expect(out.single.text, '真人输入');
    });

    test('每个 turn 只保留最后 step 的最终回答，过程文本丢弃', () {
      final out = parseHistory([
        _userEvent(seq: 1, turn: 1, text: '第一问'),
        _assistantEvent(
          seq: 2,
          turn: 1,
          step: 1,
          blocks: [
            {'type': 'text', 'text': '过程文本'},
            {'type': 'tool-call', 'name': 'read'},
          ],
        ),
        _assistantEvent(
          seq: 3,
          turn: 1,
          step: 2,
          blocks: [
            {'type': 'reasoning', 'text': '思考内容'},
            {'type': 'text', 'text': '最终回答一'},
          ],
        ),
        _userEvent(seq: 4, turn: 2, text: '第二问'),
        _assistantEvent(
          seq: 5,
          turn: 2,
          step: 1,
          blocks: [
            {'type': 'text', 'text': '只有工具调用'},
            {'type': 'tool-call', 'name': 'edit'},
          ],
        ),
      ]);

      expect(out.map((m) => m.text).toList(), ['第一问', '最终回答一', '第二问']);
      expect(out[1].role, 'assistant');
      expect(out[1].text.contains('过程文本'), isFalse);
      expect(out[1].text.contains('思考内容'), isFalse);
    });

    test('保留用户 rpcId，并按 durable message id 去重', () {
      final out = parseHistory([
        _userEvent(
          seq: 1,
          turn: 1,
          text: '同一条消息',
          id: 'message-1',
          rpcId: 'rpc-1',
        ),
        _userEvent(
          seq: 2,
          turn: 1,
          text: '同一条消息',
          id: 'message-1',
          rpcId: 'rpc-1',
        ),
      ]);
      expect(out, hasLength(1));
      expect(out.single.rpcId, 'rpc-1');
    });
  });
}

Map<String, dynamic> _userEvent({
  required int seq,
  required int turn,
  required String text,
  String? id,
  String? rpcId,
}) {
  return {
    'type': 'event',
    'event': {
      'type': 'user/message',
      'seq': seq,
      'data': {
        'id': id ?? 'message-$seq',
        'content': [
          {'type': 'text', 'text': text}
        ],
        'source': {
          'kind': 'user',
          if (rpcId != null) 'rpcId': rpcId,
        },
      },
    },
  };
}

Map<String, dynamic> _assistantEvent({
  required int seq,
  required int turn,
  required int step,
  required List<Map<String, dynamic>> blocks,
}) {
  return {
    'type': 'event',
    'event': {
      'type': 'assistant/message',
      'seq': seq,
      'data': {
        'turn': turn,
        'step': step,
        'message': {
          'role': 'assistant',
          'content': blocks,
        },
      },
    },
  };
}
