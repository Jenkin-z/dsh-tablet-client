/// 三个用户可见缺陷的回归测试
///
/// 全部来自用户实测报告：
/// 1. 「进行中」按钮永久卡住（重连重放 api-session/status 的 running:true）
/// 2. 未读一直清不掉、数字涨到 103（markSeen 从未被调用 + 全部已读 scope 不一致）
/// 3. 顶部状态点一直绿色（_sessionsOk == null 被当成健康）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/connection_health.dart';
import 'package:dsh_tablet_client/services/dsh_session_state.dart';

void main() {
  group('状态点：null 不能算健康', () {
    test('未验证过 → 连接中（橙），不是绿', () {
      final s = DshSessionState();
      s.setConnecting(false);
      s.setConnected(true);
      // 还没跑过任何 session/list，_sessionsOk 仍是 null
      expect(s.health, ConnectionHealth.connecting,
          reason: 'socket 通了但数据还没验证过，不能显示绿色');
    });

    test('验证成功 → 绿', () {
      final s = DshSessionState();
      s.setConnecting(false);
      s.setConnected(true);
      s.setSessionsHealth(ok: true);
      expect(s.health, ConnectionHealth.healthy);
    });

    test('验证失败 → 数据异常（橙），不是绿', () {
      final s = DshSessionState();
      s.setConnecting(false);
      s.setConnected(true);
      s.setSessionsHealth(ok: false, error: 'boom');
      expect(s.health, ConnectionHealth.degraded);
    });

    test('断开 → 红，且 reset() 之后回到橙而不是绿', () {
      final s = DshSessionState();
      s.setConnected(false);
      expect(s.health, ConnectionHealth.offline);

      s.setConnecting(false);
      s.setConnected(true);
      s.setSessionsHealth(ok: true);
      expect(s.health, ConnectionHealth.healthy);

      s.reset();
      s.setConnecting(false);
      s.setConnected(true);
      expect(s.health, ConnectionHealth.connecting,
          reason: 'reset() 把 _sessionsOk 清回 null，此时必须是「连接中」');
    });
  });

  group('未读：打开会话即已读 + 全部已读 scope 一致', () {
    late String ctrl;
    late String console;

    setUpAll(() {
      ctrl = File('lib/services/chat_controller.dart').readAsStringSync();
      console = File('lib/screens/console_screen.dart').readAsStringSync();
    });

    test('markSeen 必须真的被调用（曾经只定义、无人调用）', () {
      expect(ctrl.contains('settings.markSeen('), isTrue,
          reason: '未读唯一出口：打开/切换会话时必须调用 markSeen');
    });

    test('boot 与 switchSession 两条进入路径都清未读', () {
      expect(ctrl.contains('_markCurrentSeen'), isTrue);
      final bootIdx = ctrl.indexOf('Future<void> boot()');
      final bootBody = ctrl.substring(bootIdx, (bootIdx + 1200).clamp(0, ctrl.length));
      expect(bootBody.contains('_markCurrentSeen'), isTrue);

      final swIdx = ctrl.indexOf('Future<void> switchSession(');
      final swBody = ctrl.substring(swIdx, (swIdx + 600).clamp(0, ctrl.length));
      expect(swBody.contains('_markCurrentSeen'), isTrue);
    });

    test('全部已读清的是全量未读，不是 3 小时窗口内的子集', () {
      final idx = console.indexOf("'全部已读'");
      expect(idx >= 0, isTrue);
      // 往上取一段包含 onPressed 的上下文
      final start = (idx - 600).clamp(0, console.length);
      final window = console.substring(start, idx);
      expect(window.contains('settings.unviewedIds'), isTrue,
          reason: '计数是全量的，按钮也必须清全量，否则超窗的永远清不掉');
      expect(window.contains('unviewedKeys.toList'), isFalse,
          reason: '不能再传 3 小时窗口内的子集');
    });
  });

  group('进行中：running:true 受 turn 收尾约束', () {
    late String disp;

    setUpAll(() {
      disp = File('lib/services/mux_event_dispatcher.dart').readAsStringSync();
    });

    test('onSessionStatus 里 running:true 必须检查 _turnClosed', () {
      final idx = disp.indexOf('void onSessionStatus(');
      expect(idx >= 0, isTrue);
      final body = disp.substring(idx, (idx + 700).clamp(0, disp.length));
      expect(body.contains('_turnClosed'), isTrue,
          reason: '重连重放的 running:true 不能顶掉已收尾的会话');
      expect(body.contains('if (!running || !_turnClosed)'), isTrue,
          reason: 'running:false 永远接受；running:true 只在未收尾时接受');
    });

    test('用户发新消息要重新武装运行态（否则守卫会吞掉新一轮）', () {
      final idx = disp.indexOf('void onUserMessage(');
      expect(idx >= 0, isTrue);
      final body = disp.substring(idx, (idx + 1400).clamp(0, disp.length));
      expect(body.contains('_turnClosed = false'), isTrue,
          reason: '用户发了消息就是新一轮开始，必须清掉收尾标记');
    });
  });
}
