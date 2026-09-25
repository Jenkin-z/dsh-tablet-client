import 'package:flutter/material.dart';

/// 设计系统 —— 低饱和度极简风格
///
/// 参考 TraeCode 等极简应用：柔和配色、大量留白、克制的阴影。
class IosTheme {
  IosTheme._();

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

  // ── 间距系统 ─────────────────────────────────────

  static const double spaceXXS = 2.0;
  static const double spaceXS = 4.0;
  static const double spaceS = 8.0;
  static const double spaceM = 12.0;
  static const double spaceL = 16.0;
  static const double spaceXL = 20.0;
  static const double spaceXXL = 24.0;
  static const double spaceXXXL = 32.0;

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

  // ── 动画曲线 ─────────────────────────────────────

  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 350);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Curve curveSpring = Curves.easeOutCubic;
  static const Curve curveEaseInOut = Curves.easeInOut;

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

/// iOS 风格分组列表 —— 带圆角背景的内嵌列表
class IosGroupedList extends StatelessWidget {
  final List<Widget> children;
  final Widget? header;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final bool inset;

  const IosGroupedList({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.padding,
    this.inset = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? IosTheme.iosDarkGroupedBg
        : IosTheme.iosGroupedBg;
    final cardColor = isDark
        ? const Color(0xFF1E1E1E)
        : Colors.white;

    return ColoredBox(
      color: bgColor,
      child: ListView(
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: IosTheme.spaceL,
              vertical: IosTheme.spaceM,
            ),
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: IosTheme.spaceS),
          ],
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(IosTheme.radiusCard),
              boxShadow: IosTheme.shadowS,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF0F0F0),
                      margin: const EdgeInsets.only(left: 56),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: IosTheme.spaceS),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// 页面大标题
class IosPageTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const IosPageTitle({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceXL,
        IosTheme.spaceS,
        IosTheme.spaceL,
        IosTheme.spaceS,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Section Header（大写字母标签）
class IosSectionHeader extends StatelessWidget {
  final String title;

  const IosSectionHeader({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: IosTheme.spaceL + 4,
        bottom: IosTheme.spaceXS,
        top: IosTheme.spaceXS,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: IosTheme.iosGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// iOS 风格列表项
class IosListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? contentPadding;

  const IosListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.backgroundColor,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: contentPadding ??
              const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceL,
                vertical: IosTheme.spaceM,
              ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: IosTheme.spaceM),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null) title!,
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: IosTheme.spaceS),
                trailing!,
              ],
              if (showChevron && trailing == null) ...[
                const SizedBox(width: IosTheme.spaceS),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: IosTheme.iosGray3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 极简卡片
class IosCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;

  const IosCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isDark ? const Color(0xFF1E1E1E) : Colors.white),
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        boxShadow: IosTheme.shadowS,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 极简按钮
class IosButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool destructive;
  final IconData? icon;

  const IosButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = true,
    this.destructive = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? IosTheme.iosRed : IosTheme.iosBlue;
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusButton),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: IosTheme.spaceL,
            vertical: IosTheme.spaceM,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: IosTheme.spaceS),
            ],
            Text(label),
          ],
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusButton),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceM,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: IosTheme.spaceS),
          ],
          Text(label),
        ],
      ),
    );
  }
}

/// iOS 风格开关
class IosSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const IosSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: enabled ? onChanged : null,
      activeThumbColor: Colors.white,
      activeTrackColor: IosTheme.iosGreen,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: IosTheme.iosGray3,
    );
  }
}

/// 状态点
class IosStatusDot extends StatelessWidget {
  final Color color;
  final double size;

  const IosStatusDot({
    super.key,
    required this.color,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 徽标
class IosBadge extends StatelessWidget {
  final int count;
  final bool showDot;

  const IosBadge({
    super.key,
    this.count = 0,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showDot) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: IosTheme.iosRed,
          shape: BoxShape.circle,
        ),
      );
    }
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: IosTheme.iosRed,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
