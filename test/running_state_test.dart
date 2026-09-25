/// 运行态收敛回归测试
///
/// 锁定「停止按钮永久卡在进行中」这个 bug：
/// `turn/end` 之后如果还有迟到的 assistant chunk 进来，
/// 旧代码会无条件把 agentRunning 又置回 true，而之后不会再有
/// turn/end 来收尾 —— 按钮就再也回不到「发送」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/dsh_session_state.dart';
import 'package:dsh_tablet_client/services/mux_event_dispatcher.dart';

void main() {
  late DshSessionState state;
  late MuxEventDispatcher dispatcher;

  setUp(() {
    state = DshSessionState();
    dispatcher = MuxEventDispatcher(state: state);
    state.setSessionId('s1');
  });

  group('运行态在 turn 边界上的收敛', () {
    test('turn/start 重新武装运行态', () {
      dispatcher.onTurnEnd();
      expect(state.agentRunning, isFalse);

      dispatcher.onTurnStart();
      expect(state.agentRunning, isTrue);
    });

    test('turn/end 之后迟到的 chunk 不会把运行态顶回去', () async {
      dispatcher.onTurnStart();
      dispatcher.onTurnEnd();
      expect(state.agentRunning, isFalse);

      // 迟到/乱序/重连补发的增量：绝不能让按钮卡在「停止」
      dispatcher.onTextDelta('late chunk');
      // 增量是 120ms 合并后落地的，等它真的 flush 一次
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(state.agentRunning, isFalse,
          reason: '本轮已结束，迟到增量不该把运行态重新拉起');
    });

    test('turn/end 清空运行中与流式，并记录收尾时间', () {
      dispatcher.onTurnStart();
      dispatcher.onTextDelta('abc');
      dispatcher.onTurnEnd();

      expect(state.agentRunning, isFalse);
      expect(state.assistantStreaming, isFalse);
      expect(state.activeTool, isNull);
      expect(state.lastTurnEnd, isNotNull);
    });

    test('正常轮次里 chunk 仍然会把运行态拉起来', () async {
      dispatcher.onTurnStart();
      dispatcher.onTextDelta('hi');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(state.agentRunning, isTrue,
          reason: '本轮进行中的增量必须维持运行态');
    });

    test('reset 后新一轮能正常重新武装', () {
      dispatcher.onTurnEnd();
      dispatcher.reset();
      dispatcher.onTurnStart();
      expect(state.agentRunning, isTrue);
    });
  });

  group('会话级运行态写入', () {
    test('api-session/status 只影响对应会话的 agentRunning', () {
      dispatcher.onSessionStatus('s1', true);
      expect(state.agentRunning, isTrue);

      // 别的会话的状态不该改到当前会话
      dispatcher.onSessionStatus('other', false);
      expect(state.agentRunning, isTrue);
    });
  });
}
