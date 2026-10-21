/// 扫码页无效码提示节流单测
///
/// 锁死的语义：
/// - 逐帧变化的误读（二维码只进了一半）不弹提示；
/// - 同一条内容连续识别到第 2 次才提示（稳定扫到但认不出）；
/// - 提示后同内容按冷却时间节流，不连环轰炸；
/// - 识别到有效码后 reset，下一条内容重新计数。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/utils/qr_invalid_guard.dart';

void main() {
  group('QrInvalidGuard', () {
    test('第一次见到某条内容不提示（可能是半帧误读）', () {
      final g = QrInvalidGuard();
      expect(g.shouldReport('abc'), isFalse);
    });

    test('同一条内容连续第 2 次才提示', () {
      final g = QrInvalidGuard();
      expect(g.shouldReport('abc'), isFalse);
      expect(g.shouldReport('abc'), isTrue);
    });

    test('内容每次都变 → 一直不提示', () {
      final g = QrInvalidGuard();
      for (var i = 0; i < 5; i++) {
        expect(g.shouldReport('frame-$i'), isFalse);
      }
    });

    test('提示后同内容在冷却期内不再提示', () {
      final g = QrInvalidGuard();
      final t0 = DateTime(2026, 1, 1, 12);
      expect(g.shouldReport('abc', now: t0), isFalse);
      expect(g.shouldReport('abc', now: t0.add(const Duration(milliseconds: 100))),
          isTrue);
      // 冷却期内重复：不提示
      expect(
          g.shouldReport('abc', now: t0.add(const Duration(seconds: 1))), isFalse);
      // 冷却过后：再提示
      expect(
          g.shouldReport('abc', now: t0.add(const Duration(seconds: 5))), isTrue);
    });

    test('换内容后重新计数并立即提示', () {
      final g = QrInvalidGuard();
      expect(g.shouldReport('abc'), isFalse);
      expect(g.shouldReport('abc'), isTrue);
      expect(g.shouldReport('xyz'), isFalse);
      expect(g.shouldReport('xyz'), isTrue);
    });

    test('reset 后计数清零', () {
      final g = QrInvalidGuard();
      expect(g.shouldReport('abc'), isFalse);
      g.reset();
      expect(g.shouldReport('abc'), isFalse);
      expect(g.shouldReport('abc'), isTrue);
    });
  });
}
