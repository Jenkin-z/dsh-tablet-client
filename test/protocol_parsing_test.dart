/// 协议解析回归测试
///
/// 这些用例锁定的是**曾经写错、且表面上不报错**的线形：
/// 把真实报文喂进来，防止再次悄悄回归。
///
/// 报文取自 DSH 源码 / 测试（见 docs/MUX_PROTOCOL.md 的证据表）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/pending.dart';
import 'package:dsh_tablet_client/services/mux_history.dart';
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
  });
}
