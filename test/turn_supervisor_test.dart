/// TurnSupervisor 契约测试（对标 dsh-go Runtime Supervisor / Transaction）
///
/// 锁定：
/// 1. 迁移矩阵：idle→sending→running→idle；turn/end 队列非空→queued→turn/start→running；
/// 2. 闸门：turn/end 后迟到的 running:true 被拒绝，running:false 永远接受；
/// 3. 事务性：一个命令恰好一次广播（UI 不见中间帧）；
/// 4. generation 单调；同态命令不 bump、不广播；
/// 5. 审计环记录迁移与拒绝。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/turn_state.dart';
import 'package:dsh_tablet_client/services/session_state.dart';
import 'package:dsh_tablet_client/services/turn_supervisor.dart';

void main() {
  late SessionState state;
  late TurnSupervisor sup;
  bool queuedWork;

  setUp(() {
    state = SessionState();
    state.setSessionId('s1');
    queuedWork = false;
    sup = TurnSupervisor(state, hasQueuedWork: () => queuedWork);
  });

  group('迁移矩阵', () {
    test('发送链路：idle → sending →（durable 回显）→ running', () {
      expect(state.turn.phase, TurnPhase.idle);
      sup.beginLocalSend();
      expect(state.turn.phase, TurnPhase.sending);
      expect(state.agentRunning, isTrue, reason: 'busy 立即可见');
      sup.userMessageArrived();
      expect(state.turn.phase, TurnPhase.running);
    });

    test('发送失败：sending 回滚到 idle；权威 running 不被压平', () {
      sup.beginLocalSend();
      sup.failLocalSend();
      expect(state.turn.phase, TurnPhase.idle);

      // 已被权威拉起时不回滚（旧实现会无条件压平权威状态，属顺带修复）
      sup.turnStart();
      sup.failLocalSend();
      expect(state.turn.phase, TurnPhase.running);
    });

    test('turn/end 队列空 → idle；队列非空 → queued，turn/start 转 running', () {
      sup.turnStart();
      sup.toolCall('bash · ls');
      sup.turnEnd();
      expect(state.turn.phase, TurnPhase.idle);
      expect(state.turn.turnClosed, isTrue);

      queuedWork = true;
      sup.turnStart();
      sup.turnEnd();
      expect(state.turn.phase, TurnPhase.queued);
      expect(state.agentRunning, isTrue,
          reason: '排队中也是忙：停止按钮不得闪断');
      sup.turnStart();
      expect(state.turn.phase, TurnPhase.running);
    });

    test('queuePending：本轮已收尾且队列非空才落 queued', () {
      sup.queuePending();
      expect(state.turn.phase, TurnPhase.idle, reason: '闸门未收尾时不生效');

      sup.turnStart();
      sup.turnEnd();
      queuedWork = true;
      sup.queuePending();
      expect(state.turn.phase, TurnPhase.queued);

      queuedWork = false;
      sup.queueDrained();
      expect(state.turn.phase, TurnPhase.idle,
          reason: '队列清空而新轮未到，queued 是空投影必须退场');
    });

    test('权威 running:false 从任何相位落 idle 并收工具/打字机', () {
      sup.turnStart();
      sup.toolCall('bash · top');
      sup.streamTick();
      sup.authorityRunning(false);
      expect(state.turn.phase, TurnPhase.idle);
      expect(state.turn.activeTool, isNull);
      expect(state.turn.streaming, isFalse);
    });

    test('streamTick / toolCall / assistantStreamStart 的运行位', () {
      sup.beginLocalSend();
      sup.streamTick();
      // 未收尾时 flush 与旧实现一致：无条件把运行位拉起来
      expect(state.turn.phase, TurnPhase.running);
      expect(state.turn.streaming, isTrue);

      sup.toolCall('read · a.dart');
      expect(state.turn.activeTool, 'read · a.dart');
      expect(state.turn.streaming, isFalse, reason: '工具调用收掉打字机态');
      sup.toolResult();
      expect(state.turn.activeTool, isNull);
    });
  });

  group('闸门（迟到事件防护）', () {
    test('turn/end 后重放 running:true 被拒绝', () {
      sup.turnStart();
      sup.turnEnd();
      final genBefore = state.turn.generation;
      sup.authorityRunning(true);
      expect(state.turn.phase, TurnPhase.idle,
          reason: '重连重放的 running:true 不能顶掉已收尾的会话');
      expect(state.turn.generation, genBefore);
    });

    test('userMessageArrived / assistantStreamStart / turnStart 重新武装', () {
      sup.turnStart();
      sup.turnEnd();
      sup.userMessageArrived();
      expect(state.turn.turnClosed, isFalse);
      // 重新武装后 running:true 可接受
      sup.authorityRunning(true);
      expect(state.turn.phase, TurnPhase.running);

      sup.turnEnd();
      sup.assistantStreamStart();
      expect(state.turn.turnClosed, isFalse);
      expect(state.turn.phase, TurnPhase.running);
    });
  });

  group('事务性与簿记', () {
    test('一个命令恰好一次广播', () {
      var notifies = 0;
      state.addListener(() => notifies++);
      sup.turnStart();
      sup.turnEnd();
      // turnEnd 覆盖 phase/streaming/tool/closed 四个字段也只广播一次
      expect(notifies, 2, reason: '旧实现 turn/end 连调 6 个 setter 广播 6 次');
    });

    test('同态命令不 bump generation、不广播', () {
      sup.turnStart();
      final gen = state.turn.generation;
      var notifies = 0;
      state.addListener(() => notifies++);
      sup.turnStart();
      sup.toolResult();
      expect(state.turn.generation, gen);
      expect(notifies, 0);
    });

    test('generation 严格单调；CAS 丢弃旧快照', () {
      final g0 = state.turn.generation;
      sup.beginLocalSend();
      sup.turnStart();
      sup.turnEnd();
      expect(state.turn.generation, greaterThan(g0));
      final current = state.turn;
      // 旧快照重放：generation 不大于当前 → 丢弃
      state.applyTurnState(current.copyWith(phase: TurnPhase.running));
      expect(state.turn.phase, current.phase);
    });

    test('审计环：记录迁移与拒绝，封顶 50 条', () {
      for (var i = 0; i < 60; i++) {
        sup.turnStart();
        sup.turnEnd();
      }
      expect(sup.auditLog.length, 50);
      expect(sup.auditLog.last, contains('turnEnd'));
      sup.turnStart();
      sup.turnEnd();
      sup.authorityRunning(true); // 被闸门拒绝，也要留痕
      expect(sup.auditLog.any((l) => l.contains('拒绝')), isTrue);
    });

    test('reset 回初始态', () {
      sup.turnStart();
      sup.toolCall('x');
      sup.reset();
      expect(state.turn.phase, TurnPhase.idle);
      expect(state.turn.generation, greaterThan(0),
          reason: 'reset 本身也是一次有效迁移');
    });
  });
}
