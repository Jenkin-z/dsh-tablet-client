part of 'ios_theme.dart';

/// 设计系统 —— 圆角与间距层
///
/// DESIGN.md §5：卡 16 / 小卡与输入 12 / pill 999 / sheet 顶部 20。
/// 实际引用请经由 `IosTheme` 转发。
class IosRadius {
  IosRadius._();

  // ── 圆角系统 ─────────────────────────────────────

  static const double radiusXS = 8.0;
  static const double radiusS = 12.0;
  static const double radiusM = 14.0;
  static const double radiusL = 18.0;
  static const double radiusXL = 22.0;

  /// 卡片
  static const double radiusCard = 16.0;

  /// 小卡 / 按钮 / 输入
  static const double radiusButton = 12.0;

  /// 输入
  static const double radiusInput = 12.0;

  /// 胶囊 pill
  static const double radiusPill = 999.0;

  /// chip（胶囊）
  static const double radiusChip = 999.0;

  /// sheet 顶部
  static const double radiusSheet = 20.0;

  /// 头像
  static const double radiusAvatar = 24.0;
}

/// 设计系统 —— 间距层（4pt 网格）
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
///
/// DESIGN.md §7：150–250ms、指数缓出 cubic-bezier(0.25, 1, 0.3, 1)；
/// 动效只表达状态（进入 sheet、心跳滑入、流式光标、状态点呼吸）。
class IosMotion {
  IosMotion._();

  // ── 动画曲线 ─────────────────────────────────────

  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 200);
  static const Duration durationSlow = Duration(milliseconds: 250);

  /// 指数缓出（签名动效曲线）
  static const Curve curveSpring = Cubic(0.25, 1.0, 0.3, 1.0);
  static const Curve curveEaseInOut = Curves.easeInOut;

  /// 心跳刻度滑入（620ms，每 8s 一次的"活着"的证据）
  static const Duration durationPulse = Duration(milliseconds: 620);

  /// 流式光标步进（1s 闪烁）
  static const Duration durationCaret = Duration(milliseconds: 1000);
}

/// 设计系统 —— 字阶层（DESIGN.md §4 固定字阶，1.125–1.2 比率）
class IosType {
  IosType._();

  /// 等宽（主机名/路径/命令/SHA/diff），只用于代码、数据、测量
  static const String mono = 'monospace';

  static const double caption = 11;
  static const double footnote = 12;
  static const double footnotePlus = 13;
  static const double body = 15;
  static const double callout = 16;
  static const double title3 = 17;
  static const double title2 = 20;
  static const double title1 = 22;
  static const double largeTitle = 28;
}

/// 设计系统 —— 分隔线层
class IosDividers {
  IosDividers._();

  // ── 分隔线（hairline） ───────────────────────────

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
