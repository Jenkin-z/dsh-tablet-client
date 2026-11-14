part of 'ios_theme.dart';

/// 设计系统 —— 阴影层
///
/// DESIGN.md §5：只有两层 ——
/// `--shadow-card: 0 1px 2px rgba(10,12,16,.06), 0 8px 24px rgba(10,12,16,.05)`；
/// `--shadow-sheet: 0 -8px 40px rgba(10,12,16,.18)`。
/// 零偏移彩色光晕禁止；深色改用描边 + 更深底。
class IosShadows {
  IosShadows._();

  // ── 阴影系统 ─────────────────────────────────────

  /// 轻卡片阴影（单层近影）
  static List<BoxShadow> get shadowS => const [
    BoxShadow(
      color: Color(0x0F0A0C10),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// 卡片阴影（DESIGN.md shadow-card 两层配方）
  static List<BoxShadow> get shadowM => const [
    BoxShadow(
      color: Color(0x0F0A0C10),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0D0A0C10),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// 同卡片阴影（设计只保留两层，粗粒度调用点共用配方）
  static List<BoxShadow> get shadowL => IosShadows.shadowM;

  /// sheet 弹层阴影（自下而上）
  static List<BoxShadow> get shadowSheet => const [
    BoxShadow(
      color: Color(0x2E0A0C10),
      blurRadius: 40,
      offset: Offset(0, -8),
    ),
  ];
}
