part of 'ios_theme.dart';

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
    final p = IosPalette.of(context);
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
                  color: p.label3,
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
    final p = IosPalette.of(context);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      decoration: BoxDecoration(
        color: backgroundColor ?? p.surface,
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        border: p.isDark ? Border.all(color: p.separator, width: 0.5) : null,
        boxShadow: p.isDark ? null : IosTheme.shadowM,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 设计规范按钮（DESIGN.md §6）
///
/// 主=accent 实心 / 次=fill / 危=danger 描边 / 破坏性=danger 文字；高度 44。
class IosButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// true=实心（主），false=fill（次）
  final bool filled;

  /// true=danger 描边（危险操作）
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
    final p = IosPalette.of(context);
    // 高度 44（DESIGN.md §6）；宽度按内容/父约束收缩，不设固定宽
    const minHeight44 = Size(0, 44);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: IosTheme.spaceS),
        ],
        Text(label),
      ],
    );

    // 破坏性/danger：描边
    if (destructive) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: p.bad,
          side: BorderSide(color: p.bad.withValues(alpha: 0.45)),
          minimumSize: minHeight44,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusButton),
          ),
          padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        ),
        child: row,
      );
    }
    // 主：accent 实心
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          minimumSize: minHeight44,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusButton),
          ),
          padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        ),
        child: row,
      );
    }
    // 次：fill
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: p.fill,
        foregroundColor: p.label,
        minimumSize: minHeight44,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusButton),
        ),
        padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      ),
      child: row,
    );
  }
}
