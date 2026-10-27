/// 通用重连退避策略测试（与后端无关：DSH mux 与 opencode SSE 共用）
///
/// 锁定两条借自 opencode-mobile 的规则：
/// - 指数退避封顶 + 随机抖动；
/// - 只有 markStable（收到首帧数据）才重置计数。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/reconnect_policy.dart';

void main() {
  group('指数退避', () {
    test('快速档内固定间隔，之后翻倍并封顶', () {
      final b = ReconnectBackoff(
          fastLimit: 3, fastDelaySec: 1, slowDelaySec: 10, maxDelaySec: 40,
          rng: Random(1));
      // 前 3 次：1s 档（±25% 抖动）
      for (var i = 0; i < 3; i++) {
        expect(b.nextDelay().inMilliseconds, inExclusiveRange(750, 1250));
      }
      // 第 4 次：10s 起步；第 5 次 20s；第 6 次 40s 封顶
      expect(b.nextDelay().inMilliseconds, inExclusiveRange(7500, 12500));
      expect(b.nextDelay().inMilliseconds, inExclusiveRange(15000, 25000));
      expect(b.nextDelay().inMilliseconds, inExclusiveRange(30000, 50000));
      // 继续失败：不超上限
      expect(b.nextDelay().inMilliseconds, lessThanOrEqualTo(50000));
    });

    test('抖动不小于 1s 基准的一半', () {
      final b = ReconnectBackoff(
          fastLimit: 20, fastDelaySec: 1, rng: Random(7));
      for (var i = 0; i < 20; i++) {
        expect(b.nextDelay().inMilliseconds, inExclusiveRange(750, 1250));
      }
    });
  });

  group('稳定连接才重置', () {
    test('markStable 之后从头退避', () {
      final b = ReconnectBackoff(
          fastLimit: 1, fastDelaySec: 2, slowDelaySec: 30, maxDelaySec: 60,
          rng: Random(3));
      b.nextDelay();
      b.nextDelay(); // 已进入慢速档
      b.markStable(); // 收到首帧
      // 重新从快速档开始
      expect(b.nextDelay().inMilliseconds, inExclusiveRange(1500, 2500));
    });

    test('不 markStable 则持续升档（半开连接场景）', () {
      final b = ReconnectBackoff(
          fastLimit: 1, fastDelaySec: 2, slowDelaySec: 30, maxDelaySec: 60,
          rng: Random(3));
      b.nextDelay();
      b.nextDelay();
      final d = b.nextDelay();
      expect(d.inMilliseconds, inExclusiveRange(45000, 75000));
    });

    test('reset 归零', () {
      final b = ReconnectBackoff(rng: Random(3));
      b.nextDelay();
      b.nextDelay();
      b.reset();
      expect(b.attempts, 0);
    });
  });
}
