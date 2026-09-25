/// 交互语义回归测试
///
/// 锁定两条原则（见 docs/STATE_AND_INTERACTION.md）：
/// 1. 手势语义唯一 —— 点设备卡只切机器，不得依据「有没有在跑会话」分叉
/// 2. 切换机器只有一个入口 —— 跨机器时不允许再发一次会话切换请求
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/session_router.dart';

void main() {
  group('SessionRouter：切换请求是一次性的', () {
    test('request 递增 token，consume 只成功一次', () {
      final r = SessionRouter();
      r.request('srv-a', 'sess-1');
      final t = r.token;
      expect(r.serverId, 'srv-a');
      expect(r.sessionId, 'sess-1');

      expect(r.consume(t), isTrue, reason: '第一次应当取走');
      expect(r.consume(t), isFalse, reason: '同一个 token 不能消费两次');
    });

    test('新请求产生新 token，旧 token 立即失效', () {
      final r = SessionRouter();
      r.request('srv-a', 'sess-1');
      final old = r.token;
      r.request('srv-b', 'sess-2');
      expect(r.consume(old), isFalse, reason: '被更新的请求顶掉');
      expect(r.consume(r.token), isTrue);
    });

    test('只切机器（sessionId 为 null）是合法请求', () {
      final r = SessionRouter();
      r.request('srv-a', null);
      expect(r.serverId, 'srv-a');
      expect(r.sessionId, isNull);
      expect(r.consume(r.token), isTrue);
    });
  });

  group('控制台：点设备卡不得按 running 分叉', () {
    late String src;

    setUpAll(() {
      final f = File('lib/screens/console_screen.dart');
      expect(f.existsSync(), isTrue);
      src = f.readAsStringSync();
    });

    test('设备卡点击回调里不出现 running.isNotEmpty 分支', () {
      // 反例（已删除）：
      //   if (group.running.isNotEmpty) { onOpenSession(...) } else { onSwitchServer(...) }
      // 同一个手势两种结果，用户感受就是「有时进对话有时不进」
      final idx = src.indexOf('onTapDevice:');
      expect(idx >= 0, isTrue, reason: '找不到设备卡点击回调');
      final window = src.substring(idx, (idx + 700).clamp(0, src.length));
      expect(window.contains('running.isNotEmpty'), isFalse,
          reason: '设备卡点击不能依赖 running 状态分叉');
      expect(window.contains('onSwitchServer'), isTrue,
          reason: '点设备卡必须切机器');
    });

    test('未配对机器仍然引导去配对页', () {
      final idx = src.indexOf('onTapDevice:');
      final window = src.substring(idx, (idx + 700).clamp(0, src.length));
      expect(window.contains('unpaired'), isTrue);
      expect(window.contains('PairScreen'), isTrue);
    });
  });

  group('切换机器：跨机器不重复下发会话切换', () {
    late String shell;
    late String chat;

    setUpAll(() {
      shell = File('lib/screens/main_shell.dart').readAsStringSync();
      chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    });

    test('MainShell 跨机器时不再发路由请求', () {
      final idx = shell.indexOf('Future<void> _openSession');
      expect(idx >= 0, isTrue);
      final window = shell.substring(idx, (idx + 900).clamp(0, shell.length));
      expect(window.contains('machineChanged'), isTrue,
          reason: '必须显式区分机器是否变了');
      // 只有「同机器」那条分支才允许发路由
      expect(window.contains('if (!machineChanged)'), isTrue,
          reason: '跨机器靠 ChatScreen key 重建，不该再发路由请求');
    });

    test('ChatScreen 收到非当前机器的路由请求时直接丢弃', () {
      final idx = chat.indexOf('void _onRouteRequest');
      expect(idx >= 0, isTrue);
      final window = chat.substring(idx, (idx + 900).clamp(0, chat.length));
      expect(window.contains('router.consume(router.token)'), isTrue,
          reason: '丢弃时也要消费掉 token，避免残留');
    });
  });
}
