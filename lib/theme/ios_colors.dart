part of 'ios_theme.dart';

/// 设计系统 —— 色彩层
///
/// DESIGN.md §3：中性色取"冷石墨"家族 + 一个交互强调色（青碧 teal），
/// 语义色（绿/橙/红）承担真实信息工作；浅色（日光）与深色（冷夜，微偏蓝石墨）
/// 同等第一公民。
///
/// 两个入口：
/// - `IosColors.*` 旧常量名：浅色基准值，兼容既有 `IosTheme.*` 调用点（值已校准）。
/// - `IosPalette.of(context)`：按亮度解析的完整 token 集，新代码一律用它。
class IosColors {
  IosColors._();

  // ── 旧常量名（浅色基准，保持既有引用有效） ─────────

  /// 主色调 → accent（青碧 teal，浅色）
  static const Color iosBlue = Color(0xFF1F7A8C);

  /// 成功 ok（浅色）
  static const Color iosGreen = Color(0xFF2E8F5B);

  /// 错误/危险 bad（浅色）
  static const Color iosRed = Color(0xFFC24A3F);

  /// 警告 warn tint（浅色）
  static const Color iosOrange = Color(0xFFC58221);

  /// 强调琥珀（深色 warn 基准）
  static const Color iosYellow = Color(0xFFE0AC55);

  /// 辅助紫（装饰，非强调）
  static const Color iosPurple = Color(0xFF9B8FD8);

  /// 辅助粉（装饰）
  static const Color iosPink = Color(0xFFD98B9E);

  /// 辅助青（深色 accent 基准）
  static const Color iosTeal = Color(0xFF58B7C6);

  // ── 灰阶（冷石墨，浅色基准） ─────────────────────

  /// 主文字 label
  static const Color iosGray = Color(0xFF16181D);

  /// 次级 label-2
  static const Color iosGray2 = Color(0xFF63676F);

  /// 三级/占位 label-3
  static const Color iosGray3 = Color(0xFF989CA4);

  /// 分隔线（实底近似，优先用 [IosPalette.separator]）
  static const Color iosGray4 = Color(0xFFD9D9DE);

  /// 卡内嵌套 surface-2
  static const Color iosGray5 = Color(0xFFF7F7FA);

  /// 页面地 bg（浅色）
  static const Color iosGroupedBg = Color(0xFFF2F2F6);

  /// 页面地 bg（深色，冷夜微偏蓝）
  static const Color iosDarkGroupedBg = Color(0xFF0B0C0F);
}

/// 按亮度解析的设计 token 集（DESIGN.md §3 全表）
class IosPalette {
  const IosPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.elevated,
    required this.label,
    required this.label2,
    required this.label3,
    required this.separator,
    required this.fill,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.ok,
    required this.okSoft,
    required this.warnText,
    required this.warnTint,
    required this.warnSoft,
    required this.bad,
    required this.badSoft,
  });

  final bool isDark;

  // ── 中性（冷石墨） ──────────────────────────────

  /// 页面地
  final Color bg;

  /// 卡片 / 分组容器
  final Color surface;

  /// 卡内嵌套区 / 输入底
  final Color surface2;

  /// sheet / 弹层
  final Color elevated;

  /// 主文字
  final Color label;

  /// 次级文字
  final Color label2;

  /// 三级 / 占位
  final Color label3;

  /// 分隔线 hairline
  final Color separator;

  /// 细碎填充
  final Color fill;

  // ── 强调与语义 ─────────────────────────────────

  /// 交互 tint：主按钮、激活 Tab、链接、选中项
  final Color accent;

  /// 选中底 / 强调软底
  final Color accentSoft;

  /// accent 上的文字
  final Color onAccent;

  /// healthy / 进行中
  final Color ok;

  /// ok 软底
  final Color okSoft;

  /// warn 文字级（connecting / degraded / 排队 / 待查看）
  final Color warnText;

  /// warn tint 级（徽标底、图形）
  final Color warnTint;

  /// warn 软底
  final Color warnSoft;

  /// offline / 拒绝 / 失败
  final Color bad;

  /// bad 软底
  final Color badSoft;

  /// 按上下文取浅/深两套。
  static IosPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 无 context 场景按亮度取。
  static IosPalette ofBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 浅色（日光）
  static const IosPalette light = IosPalette(
    isDark: false,
    bg: Color(0xFFF2F2F6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F7FA),
    elevated: Color(0xFFFFFFFF),
    label: Color(0xFF16181D),
    label2: Color(0xFF63676F),
    label3: Color(0xFF989CA4),
    separator: Color(0x1A16181D),
    fill: Color(0x0F16181D),
    accent: Color(0xFF1F7A8C),
    accentSoft: Color(0x1F1F7A8C),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF2E8F5B),
    okSoft: Color(0x1F2E8F5B),
    warnText: Color(0xFFB06D0C),
    warnTint: Color(0xFFC58221),
    warnSoft: Color(0x24C58221),
    bad: Color(0xFFC24A3F),
    badSoft: Color(0x1FC24A3F),
  );

  /// 深色（冷夜）
  static const IosPalette dark = IosPalette(
    isDark: true,
    bg: Color(0xFF0B0C0F),
    surface: Color(0xFF17191D),
    surface2: Color(0xFF1F2227),
    elevated: Color(0xFF23262C),
    label: Color(0xFFF0F2F5),
    label2: Color(0xFF9BA2AB),
    label3: Color(0xFF78808A),
    separator: Color(0x24F0F2F5),
    fill: Color(0x14F0F2F5),
    accent: Color(0xFF58B7C6),
    accentSoft: Color(0x2958B7C6),
    onAccent: Color(0xFF08262C),
    ok: Color(0xFF4CC97E),
    okSoft: Color(0x294CC97E),
    warnText: Color(0xFFE0AC55),
    warnTint: Color(0xFFE0AC55),
    warnSoft: Color(0x29E0AC55),
    bad: Color(0xFFE4695B),
    badSoft: Color(0x29E4695B),
  );
}
