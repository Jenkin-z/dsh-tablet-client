part of 'ios_theme.dart';

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
    final p = IosPalette.of(context);
    return ColoredBox(
      color: p.bg,
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
              color: p.surface,
              borderRadius: BorderRadius.circular(IosTheme.radiusCard),
              border: p.isDark
                  ? Border.all(color: p.separator, width: 0.5)
                  : null,
              boxShadow: p.isDark ? null : IosTheme.shadowM,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      color: p.separator,
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
    final p = IosPalette.of(context);
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
              style: TextStyle(
                color: p.label,
                fontSize: IosType.title1,
                fontWeight: FontWeight.w600,
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
    final p = IosPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: IosTheme.spaceL + 4,
        bottom: IosTheme.spaceXS,
        top: IosTheme.spaceXS,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: p.label2,
          fontSize: IosType.caption,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
