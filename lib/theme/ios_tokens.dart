part of 'ios_theme.dart';

/// 设计系统 —— 圆角与间距层
///
/// 实际引用请经由 `IosTheme` 转发。
class IosRadius {
  IosRadius._();

  // ── 圆角系统 ─────────────────────────────────────

  static const double radiusXS = 8.0;
  static const double radiusS = 12.0;
  static const double radiusM = 14.0;
  static const double radiusL = 18.0;
  static const double radiusXL = 22.0;
  static const double radiusCard = 14.0;
  static const double radiusButton = 10.0;
  static const double radiusInput = 10.0;
  static const double radiusChip = 20.0;
  static const double radiusAvatar = 24.0;
}

/// 设计系统 —— 间距层
class IosSpacing {
  IosSpacing._();

  // ── 间距系统 ─────────────────────────────────────

  static const double spaceXXS = 2.0;
  static const double spaceXS = 4.0;
  static const double spaceS = 8.0;
  static const double spaceM = 12.0;
  static const double spaceL = 16.0;
  static const double spaceXL = 20.0;
  static const double spaceXXL = 24.0;
  static const double spaceXXXL = 32.0;
}

/// 设计系统 —— 动效层
class IosMotion {
  IosMotion._();

  // ── 动画曲线 ─────────────────────────────────────

  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 350);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Curve curveSpring = Curves.easeOutCubic;
  static const Curve curveEaseInOut = Curves.easeInOut;
}

/// 设计系统 —— 分隔线层
class IosDividers {
  IosDividers._();

  // ── 分隔线 ──────────────────────────────────────

  static const Divider divider = Divider(
    height: 0.5,
    thickness: 0.5,
    indent: 0,
    endIndent: 0,
  );

  static const Divider dividerInset = Divider(
    height: 0.5,
    thickness: 0.5,
    indent: 56,
    endIndent: 0,
  );
}
