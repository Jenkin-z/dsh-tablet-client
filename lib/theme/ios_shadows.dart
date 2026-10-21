part of 'ios_theme.dart';

/// 设计系统 —— 阴影层（极淡）
///
/// 实际引用请经由 `IosTheme` 转发。
class IosShadows {
  IosShadows._();

  // ── 阴影系统（极淡） ─────────────────────────────

  static List<BoxShadow> get shadowS => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get shadowM => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowL => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}
