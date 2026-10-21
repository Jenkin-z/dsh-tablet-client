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
