/// 聊天实时过滤回归测试
///
/// 锁死与 DSH Web 对齐的规则：
/// - 工具调用前的文本属于过程，工具调用到达时整条丢弃；
/// - 一个 turn 复用同一条 assistant 气泡，最终回答就地替换；
/// - turn/end 之后迟到的 chunk 不再新建气泡；
/// - 用户消息按 durable id / rpcId 去重，重连装载不重复。
library;

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/message.dart';
import 'package:dsh_tablet_client/services/event_dispatcher.dart';
import 'package:dsh_tablet_client/services/session_state.dart';

void main() {
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

  test('工具调用丢弃过程文本，最终回答只保留一条', () async {
    dispatcher.onTurnStart();
    dispatcher.onTextDelta('过程文本');
    await flush();
    expect(dispatcher.messages.single.content, '过程文本');

    dispatcher.onAssistantFinal('过程文本', false, hasToolCall: true);
    dispatcher.onToolCall('read');
    expect(dispatcher.messages, isEmpty);

    dispatcher.onTextDelta('最终回答');
    await flush();
    dispatcher.onAssistantFinal('最终回答', false);
    dispatcher.onAssistantFinal('最终回答', false);

    expect(dispatcher.messages, hasLength(1));
    expect(dispatcher.messages.single.role, 'assistant');
    expect(dispatcher.messages.single.content, '最终回答');
    expect(dispatcher.messages.single.isStreaming, isFalse);
  });

  test('turn/end 后迟到的 chunk 不新建重复气泡', () async {
    dispatcher.onTurnStart();
    dispatcher.onTextDelta('回答');
    await flush();
    dispatcher.onAssistantFinal('回答', false);
    dispatcher.onTurnEnd();

    dispatcher.onTextDelta('迟到');
    await flush();

    expect(dispatcher.messages, hasLength(1));
    expect(dispatcher.messages.single.content, '回答');
  });

  test('新 turn 重新建 assistant 气泡', () async {
    dispatcher.onTurnStart();
    dispatcher.onTextDelta('第一轮');
    await flush();
    dispatcher.onAssistantFinal('第一轮', false);
    dispatcher.onTurnEnd();

    dispatcher.onTurnStart();
    dispatcher.onTextDelta('第二轮');
    await flush();
    dispatcher.onAssistantFinal('第二轮', false);

    expect(dispatcher.messages.map((m) => m.content).toList(), ['第一轮', '第二轮']);
  });

  test('durable 用户消息按 id 去重，rpcId 回显只保留一条', () {
    dispatcher.addLocalUserMessage('你好', 'rpc-1');
    dispatcher.onUserMessage('你好', 'rpc-1', '1', 'message-1');
    dispatcher.onUserMessage('你好', 'rpc-1', '2', 'message-1');

    expect(dispatcher.messages, hasLength(1));
    expect(dispatcher.messages.single.role, 'user');
    expect(dispatcher.messages.single.pending, isFalse);
    expect(dispatcher.messages.single.rpcId, 'rpc-1');
  });

  test('历史装载已含同一 rpcId 时不再补本地回显', () {
    dispatcher.addLocalUserMessage('你好', 'rpc-1');
    dispatcher.onHistoryLoaded([
      ChatMessage(
        id: 'u1',
        role: 'user',
        content: '你好',
        rpcId: 'rpc-1',
      ),
    ]);

    expect(dispatcher.messages, hasLength(1));
    expect(dispatcher.messages.single.id, 'u1');
  });
}
