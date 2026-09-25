/// 状态点语义与颜色回归测试
///
/// 用户实测：对话页顶部的点「一直不变」，始终绿色。
///
/// 根因不是颜色算错，而是**两个独立信号被写进了同一个字段**：
/// ServerManager 每 8 秒对当前机器做一次 HTTP 轮询，成功就写
/// `setSessionsHealth(ok: true)` → 绿。于是无论对话页那条 WebSocket
/// 是死是活，只要轮询活着，点就恒绿。
///
/// Web 端不做轮询（packages/client 里没有任何拉状态的 setInterval），
/// 它靠 $events / session/follow / session/control 推送 + 一次初始 baseline。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/connection_health.dart';
import 'package:dsh_tablet_client/services/dsh_session_state.dart';
import 'package:dsh_tablet_client/theme/ios_theme.dart';

void main() {
  group('状态点只反映对话页（mux）的数据健康', () {
    late String main;
    late String manager;

    setUpAll(() {
      main = File('lib/main.dart').readAsStringSync();
      manager = File('lib/services/server_manager.dart').readAsStringSync();
    });

    test('main.dart 不再把轮询结果接到 setSessionsHealth', () {
      // 只检查真正的调用（cascade 赋值），注释里提到这个名字是允许的
      expect(main.contains('..onActiveHealth ='), isFalse,
          reason: '轮询成功会让状态点恒绿，必须解耦');
    });

    test('ServerManager 不再对外广播轮询健康度', () {
      final idx = manager.indexOf('void _reportActiveHealth()');
      expect(idx >= 0, isTrue);
      final body = manager.substring(idx, (idx + 700).clamp(0, manager.length));
      // 注释里可以提，实际调用不行
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('onActiveHealth?.call'), isFalse,
          reason: '广播口存在就会被接错，这里不许再调用');
    });
  });

  group('四种颜色的含义', () {
    test('connecting：正在建连或数据尚未校验 → 橙「连接中」', () {
      final s = DshSessionState()..setConnecting(true);
      expect(s.health, ConnectionHealth.connecting);
      expect(_colorOf(s.health), IosTheme.iosOrange);
    });

    test('offline：连接已断开 → 红「未连接」', () {
      final s = DshSessionState()
        ..setConnecting(false)
        ..setConnected(false);
      expect(s.health, ConnectionHealth.offline);
      expect(_colorOf(s.health), IosTheme.iosRed);
    });

    test('degraded：socket 通但列表拉取失败 → 橙「数据异常」', () {
      final s = DshSessionState()
        ..setConnecting(false)
        ..setConnected(true)
        ..setSessionsHealth(ok: false, error: '列表失败');
      expect(s.health, ConnectionHealth.degraded);
      expect(_colorOf(s.health), IosTheme.iosOrange);
      expect(s.sessionsError, '列表失败');
    });

    test('healthy：连上且列表确实拉到了 → 绿「已连接」', () {
      final s = DshSessionState()
        ..setConnecting(false)
        ..setConnected(true)
        ..setSessionsHealth(ok: true);
      expect(s.health, ConnectionHealth.healthy);
      expect(_colorOf(s.health), IosTheme.iosGreen);
    });

    test('绿色必须同时满足 connected 与 sessionsOk，缺一不可', () {
      // 只连上、没校验数据 → 不是绿
      final a = DshSessionState()
        ..setConnecting(false)
        ..setConnected(true);
      expect(a.health, isNot(ConnectionHealth.healthy));

      // 校验过数据、但连接断了 → 不是绿
      final b = DshSessionState()
        ..setConnecting(false)
        ..setConnected(false)
        ..setSessionsHealth(ok: true);
      expect(b.health, isNot(ConnectionHealth.healthy));
    });
  });

  group('ChatController 在连上与重连后校准数据基线', () {
    test('onReady 与 onReconnected 都重新拉会话列表', () {
      final src = File('lib/services/chat_controller.dart').readAsStringSync();
      for (final hook in ['onReady', 'onReconnected']) {
        final idx = src.indexOf('..$hook = () {');
        expect(idx >= 0, isTrue, reason: '找不到 $hook');
        final body = src.substring(idx, (idx + 400).clamp(0, src.length));
        expect(body.contains('_refreshSessions()'), isTrue,
            reason: '$hook 之后必须校准数据基线，否则绿点是假的');
      }
    });
  });
}

/// 与 connection_status.dart 的分支保持一致（该处按 health 上色）
Color _colorOf(ConnectionHealth h) => switch (h) {
      ConnectionHealth.connecting => IosTheme.iosOrange,
      ConnectionHealth.healthy => IosTheme.iosGreen,
      ConnectionHealth.degraded => IosTheme.iosOrange,
      ConnectionHealth.offline => IosTheme.iosRed,
    };
