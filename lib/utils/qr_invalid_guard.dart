/// 扫码页的“无效码”提示节流
///
/// 相机每帧都可能识别出内容：二维码只进了一半、终端上别的字符被误读，
/// 都会解出**每次都不一样**的垃圾串。原来“第一次见到就报错”，于是
/// 用户会先看到一条红色“未识别到有效地址”，下一秒真正的二维码扫成功、
/// 绑定也成功了——看起来就像“绑定成功但提示失败”。
///
/// 规则：同一条内容**连续识别到第 2 次**才提示（说明它稳定存在，
/// 确实是扫到了而不是误读），之后同内容按冷却时间节流。
class QrInvalidGuard {
  /// 同一内容至少出现几次才提示
  final int stableThreshold;

  /// 同一条内容的提示冷却
  final Duration cooldown;

  String? _raw;
  int _count = 0;
  String? _lastReportRaw;
  DateTime? _lastReportAt;

  QrInvalidGuard({
    this.stableThreshold = 2,
    this.cooldown = const Duration(seconds: 3),
  });

  /// 记一次识别结果；返回 true 表示这次要弹错误提示
  bool shouldReport(String raw, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (raw == _raw) {
      _count++;
    } else {
      _raw = raw;
      _count = 1;
    }
    if (_count < stableThreshold) return false;
    // 同一条内容按冷却节流；换内容立即提示
    if (_lastReportRaw == raw) {
      final last = _lastReportAt;
      if (last != null && t.difference(last) < cooldown) return false;
    }
    _lastReportRaw = raw;
    _lastReportAt = t;
    return true;
  }

  /// 有效码被识别后清空状态，避免下一条内容继承上一条的计数
  void reset() {
    _raw = null;
    _count = 0;
  }
}
