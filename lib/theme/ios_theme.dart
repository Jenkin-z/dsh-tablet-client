import 'package:flutter/material.dart';

part 'ios_colors.dart';
part 'ios_shadows.dart';
part 'ios_tokens.dart';
part 'ios_widgets.dart';
part 'ios_widgets2.dart';
part 'ios_widgets3.dart';

/// 设计系统 —— 冷石墨 + teal 强调（DESIGN.md）
///
/// Operate 模式工具界面："earned familiarity" 高于表达欲。
/// 深浅双主题一等公民：新代码按上下文取 [IosPalette.of]，
/// 旧 `IosTheme.*` 静态常量保持有效（浅色基准值，已校准到新设计）。
///
/// Tokens 按层拆分在 part 文件中：
/// - `ios_colors.dart`   色彩（`IosColors` / `IosPalette`）
/// - `ios_tokens.dart`   圆角/间距/动效/字阶/分隔线
/// - `ios_shadows.dart`  阴影（`IosShadows`）
/// - `ios_widgets*.dart` 复用组件（`IosGroupedList`/`IosListTile`/`IosCard` 等）
///
/// `IosTheme` 经由上速语义层类转发，所有既有 `IosTheme.*` 引用保持有效。
class IosTheme {
  IosTheme._();

  // ── 亮度解析入口（深浅双主题） ───────────────────

  /// 按当前上下文亮度解析的完整设计 token
  static IosPalette of(BuildContext context) => IosPalette.of(context);

  // ── 色彩系统（浅色基准，兼容既有引用） ───────────

  /// 主色调：accent 青碧 teal（浅色基准）
  static const Color iosBlue = IosColors.iosBlue;
  /// 成功：ok 绿
  static const Color iosGreen = IosColors.iosGreen;
  /// 错误/危险：bad 红
  static const Color iosRed = IosColors.iosRed;
  /// 警告：warn tint 橙
  static const Color iosOrange = IosColors.iosOrange;
  /// 强调：琥珀
  static const Color iosYellow = IosColors.iosYellow;
  /// 辅助紫
  static const Color iosPurple = IosColors.iosPurple;
  /// 辅助粉
  static const Color iosPink = IosColors.iosPink;
  /// 辅助青
  static const Color iosTeal = IosColors.iosTeal;

  // ── 灰阶系统（冷石墨，浅色基准） ─────────────────

  /// 主文字
  static const Color iosGray = IosColors.iosGray;
  /// 次文字
  static const Color iosGray2 = IosColors.iosGray2;
  /// 占位/禁用
  static const Color iosGray3 = IosColors.iosGray3;
  /// 分隔线
  static const Color iosGray4 = IosColors.iosGray4;
  /// 浅背景
  static const Color iosGray5 = IosColors.iosGray5;
  /// 页面背景
  static const Color iosGroupedBg = IosColors.iosGroupedBg;
  /// 深色页面背景
  static const Color iosDarkGroupedBg = IosColors.iosDarkGroupedBg;

  // ── 圆角系统 ─────────────────────────────────────

  static const double radiusXS = IosRadius.radiusXS;
  static const double radiusS = IosRadius.radiusS;
  static const double radiusM = IosRadius.radiusM;
  static const double radiusL = IosRadius.radiusL;
  static const double radiusXL = IosRadius.radiusXL;
  static const double radiusCard = IosRadius.radiusCard;
  static const double radiusButton = IosRadius.radiusButton;
  static const double radiusInput = IosRadius.radiusInput;
  static const double radiusChip = IosRadius.radiusChip;

  /// 胶囊 pill
  static const double radiusPill = IosRadius.radiusPill;

  /// sheet 顶部
  static const double radiusSheet = IosRadius.radiusSheet;
  static const double radiusAvatar = IosRadius.radiusAvatar;

  // ── 间距系统 ─────────────────────────────────────

  static const double spaceXXS = IosSpacing.spaceXXS;
  static const double spaceXS = IosSpacing.spaceXS;
  static const double spaceS = IosSpacing.spaceS;
  static const double spaceM = IosSpacing.spaceM;
  static const double spaceL = IosSpacing.spaceL;
  static const double spaceXL = IosSpacing.spaceXL;
  static const double spaceXXL = IosSpacing.spaceXXL;
  static const double spaceXXXL = IosSpacing.spaceXXXL;

  // ── 阴影系统（极淡） ─────────────────────────────

  static List<BoxShadow> get shadowS => IosShadows.shadowS;

  static List<BoxShadow> get shadowM => IosShadows.shadowM;

  static List<BoxShadow> get shadowL => IosShadows.shadowL;

  // ── 动画曲线 ─────────────────────────────────────

  static const Duration durationFast = IosMotion.durationFast;
  static const Duration durationNormal = IosMotion.durationNormal;
  static const Duration durationSlow = IosMotion.durationSlow;
  static const Curve curveSpring = IosMotion.curveSpring;
  static const Curve curveEaseInOut = IosMotion.curveEaseInOut;

  // ── 分隔线 ──────────────────────────────────────

  static const Divider divider = IosDividers.divider;
  static const Divider dividerInset = IosDividers.dividerInset;
}
