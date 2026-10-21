import 'package:flutter/material.dart';

part 'ios_colors.dart';
part 'ios_shadows.dart';
part 'ios_tokens.dart';
part 'ios_widgets.dart';
part 'ios_widgets2.dart';
part 'ios_widgets3.dart';

/// 设计系统 —— 低饱和度极简风格
///
/// 参考 TraeCode 等极简应用：柔和配色、大量留白、克制的阴影。
///
/// Tokens 按层拆分在 part 文件中：
/// - `ios_colors.dart`   色彩（`IosColors`）
/// - `ios_tokens.dart`   圆角/间距/动效/分隔线（`IosRadius`/`IosSpacing`/`IosMotion`/`IosDividers`）
/// - `ios_shadows.dart`  阴影（`IosShadows`）
/// - `ios_widgets*.dart` 复用组件（`IosGroupedList`/`IosListTile`/`IosCard` 等）
///
/// `IosTheme` 经由上速语义层类转发，所有既有 `IosTheme.*` 引用保持有效。
class IosTheme {
  IosTheme._();

  // ── 色彩系统（低饱和度） ─────────────────────────

  /// 主色调：柔和紫蓝
  static const Color iosBlue = IosColors.iosBlue;
  /// 成功：柔和绿
  static const Color iosGreen = IosColors.iosGreen;
  /// 错误/危险：柔和红
  static const Color iosRed = IosColors.iosRed;
  /// 警告：柔和橙
  static const Color iosOrange = IosColors.iosOrange;
  /// 强调：柔和黄
  static const Color iosYellow = IosColors.iosYellow;
  /// 辅助紫
  static const Color iosPurple = IosColors.iosPurple;
  /// 辅助粉
  static const Color iosPink = IosColors.iosPink;
  /// 辅助青
  static const Color iosTeal = IosColors.iosTeal;

  // ── 灰阶系统 ─────────────────────────────────────

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
