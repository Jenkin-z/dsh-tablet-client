/// 队列域集成测试：运行中继续输入对话（排队/插话）的可见化与相位联动
///
/// 锁定（DSH `session/prompt` mode:queue 的客户端体验）：
/// 1. queue 帧解析（placement / rpcId / content blocks 拍平）；
/// 2. rpcId 对账：Host 受理 → 乐观气泡转确认态；
/// 3. 跨会话隔离：别的会话的队列不错记到当前会话；
/// 4. baseline 恢复：重连后队列视图从 control/baseline 的 queues 回来；
/// 5. 相位不闪断：turn/end 队列非空 → queued（busy 延续）→ turn/start → running；
/// 6. 队列清空而新轮未到 → 退回 idle（queued 是「队列非空」的投影）。
library;

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/queued_message.dart';
import 'package:dsh_tablet_client/models/turn_state.dart';
import 'package:dsh_tablet_client/services/event_dispatcher.dart';
import 'package:dsh_tablet_client/services/session_state.dart';

void main() {
  group('parseQueuedItems 契约', () {
    test('placement / rpcId / content 字符串', () {
      final items = parseQueuedItems([
        {
          'id': 'q1',
          'placement': 'queued',
          'rpcId': 'rpc-1',
          'message': {
            'id': 'm1',
            'content': [
              {'type': 'text', 'text': '帮我看看日志'},
            ],
          },
        },
        {
          'id': 'q2',
          'placement': 'steering',
          'message': {'id': 'm2', 'content': '等等，先停一下'},
        },
        {
          'id': 'q3',
          'placement': 'context',
          'message': {'id': 'm3', 'content': 'runtime-context'},
        },
      ]);
      expect(items.length, 3);
      expect(items[0].placement, QueuePlacement.queued);
      expect(items[0].rpcId, 'rpc-1');
      expect(items[0].content, '帮我看看日志');
      expect(items[1].placement, QueuePlacement.steering);
      expect(items[1].rpcId, isNull);
      expect(items[2].placement, QueuePlacement.context);
      expect(items[2].countsAsUserQueue, isFalse,
          reason: 'context 是上下文注入，不算用户排队');
      expect(items[0].countsAsUserQueue, isTrue);
      expect(items[1].countsAsUserQueue, isTrue);
    });

    test('脏条目跳过（缺 id）', () {
      final items = parseQueuedItems([
        {'placement': 'queued'},
        {'id': 'ok', 'message': {'content': 'x'}},
      ]);
      expect(items.length, 1);
      expect(items[0].id, 'ok');
    });
  });

  group('队列对账与相位联动', () {
    late SessionState state;
    late EventDispatcher dispatcher;

    setUp(() {
      state = SessionState();
      state.setSessionId('s1');
      dispatcher = EventDispatcher(state: state);
    });

    Map<String, dynamic> item(String id,
        {String? rpcId, String placement = 'queued', String text = 'hi'}) => {
          'id': id,
          'placement': placement,
          if (rpcId != null) 'rpcId': rpcId,
          'message': {
            'id': 'm-$id',
            'content': [
              {'type': 'text', 'text': text},
            ],
          },
        };

    test('rpcId 命中：乐观气泡转确认态', () {
      dispatcher.addLocalUserMessage('帮我看看日志', 'rpc-1');
      expect(dispatcher.messages.first.pending, isTrue);

      dispatcher.onQueueUpdate('s1', [
        item('q1', rpcId: 'rpc-1', text: '帮我看看日志'),
      ]);
      expect(dispatcher.messages.first.pending, isFalse,
          reason: 'Host 受理 = 可视确认，气泡不再显示 pending');
      expect(state.queuedCountOf('s1'), 1);
    });

    test('跨会话隔离：别的会话的队列不错记到当前会话', () {
      dispatcher.onQueueUpdate('s-other', [item('q1', rpcId: 'rpc-x')]);
      expect(state.queuedCountOf('s1'), 0);
      expect(state.queuedCountOf('s-other'), 1);
      // rpcId 是其他会话的，不能确认当前会话的乐观气泡
      dispatcher.addLocalUserMessage('本会话消息', 'rpc-x');
      expect(dispatcher.messages.last.pending, isTrue);
    });

    test('turn/end 队列非空 → queued；busy 全程不闪断；turn/start → running', () {
      dispatcher.onTurnStart();
      dispatcher.onQueueUpdate('s1', [item('q1'), item('q2')]);
      dispatcher.onTurnEnd();
      expect(state.turn.phase, TurnPhase.queued);
      expect(state.agentRunning, isTrue,
          reason: 'turn/end→turn/start 间隙 busy 延续，停止按钮不闪');

      dispatcher.onTurnStart();
      expect(state.turn.phase, TurnPhase.running);
      // Host 开跑后队列快照随之清空
      dispatcher.onQueueUpdate('s1', []);
      expect(state.queuedCountOf('s1'), 0);
    });

    test('队列清空而新轮未到：queued 退回 idle', () {
      dispatcher.onTurnStart();
      dispatcher.onTurnEnd();
      // turn/end 时队列还空 → 直接 idle（此用例先造 queued 再排空）
      dispatcher.onQueueUpdate('s1', [item('q1')]);
      expect(state.turn.phase, TurnPhase.queued,
          reason: 'turnClosed 且队列非空 → busy 延续');
      dispatcher.onQueueUpdate('s1', []);
      expect(state.turn.phase, TurnPhase.idle);
    });

    test('baseline 恢复：重连后从 control/baseline 回填队列视图', () {
      dispatcher.onControlBaseline({
        'value': {
          'queues': {
            's1': [item('q1', rpcId: 'rpc-1')],
            's2': [item('q9')],
          },
        },
      });
      expect(state.queuedCountOf('s1'), 1);
      expect(state.queuedCountOf('s2'), 1);
    });

    test('队列快照不变不重复广播', () {
      var notifies = 0;
      state.addListener(() => notifies++);
      dispatcher.onQueueUpdate('s1', [item('q1')]);
      final afterFirst = notifies;
      dispatcher.onQueueUpdate('s1', [item('q1')]);
      expect(notifies, afterFirst, reason: 'queue 帧可能重放同快照，内容未变不广播');
    });

    test('完整体验流：运行中插话 → 停止按钮全程在场', () {
      // 第一轮
      dispatcher.onTurnStart();
      expect(state.turn.busy, isTrue);
      // 运行中用户继续输入（服务端排入 steering）
      dispatcher.addLocalUserMessage('插一句：先跑测试', 'rpc-9');
      dispatcher.onQueueUpdate('s1', [
        item('q1', rpcId: 'rpc-9', placement: 'steering', text: '插一句：先跑测试'),
      ]);
      expect(dispatcher.messages.last.pending, isFalse);
      // 第一轮结束：插话还在，busy 不落
      dispatcher.onTurnEnd();
      expect(state.turn.phase, TurnPhase.queued);
      // Host 开跑第二轮
      dispatcher.onTurnStart();
      expect(state.turn.phase, TurnPhase.running);
      dispatcher.onQueueUpdate('s1', []);
    });
  });
}
