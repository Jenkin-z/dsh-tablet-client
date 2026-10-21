part of 'ios_theme.dart';

/// 设计系统 —— 色彩层
///
/// 参考 TraeCode 等极简应用：柔和配色。
/// 实际引用请经由 `IosTheme` 转发。
class IosColors {
  IosColors._();

  // ── 色彩系统（低饱和度） ─────────────────────────

  /// 主色调：柔和紫蓝
  static const Color iosBlue = Color(0xFF7C6FE0);
  /// 成功：柔和绿
  static const Color iosGreen = Color(0xFF6BBF8A);
  /// 错误/危险：柔和红
  static const Color iosRed = Color(0xFFE87070);
  /// 警告：柔和橙
  static const Color iosOrange = Color(0xFFE8A95B);
  /// 强调：柔和黄
  static const Color iosYellow = Color(0xFFE8D56B);
  /// 辅助紫
  static const Color iosPurple = Color(0xFF9B8FD8);
  /// 辅助粉
  static const Color iosPink = Color(0xFFD98B9E);
  /// 辅助青
  static const Color iosTeal = Color(0xFF7BBDD4);

  // ── 灰阶系统 ─────────────────────────────────────

  /// 主文字
  static const Color iosGray = Color(0xFF8A8A8E);
  /// 次文字
  static const Color iosGray2 = Color(0xFFAEAEB2);
  /// 占位/禁用
  static const Color iosGray3 = Color(0xFFC7C7CC);
  /// 分隔线
  static const Color iosGray4 = Color(0xFFD1D1D6);
  /// 浅背景
  static const Color iosGray5 = Color(0xFFE5E5EA);
  /// 页面背景
  static const Color iosGroupedBg = Color(0xFFF7F8FA);
  /// 深色页面背景
  static const Color iosDarkGroupedBg = Color(0xFF121212);
}
