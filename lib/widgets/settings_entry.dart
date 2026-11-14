import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 设置根页的入口行：图标 + 标题 + 当前值 + 箭头
///
/// 根页只放「去哪」，具体设置都在二级页里；`value` 显示当前状态摘要
/// （主题、开关、版本号…），一眼能看出改没改。
class SettingsEntryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  /// 右侧的当前值摘要
  final String? value;

  /// 标题下方的补充说明
  final String? subtitle;

  final VoidCallback onTap;

  const SettingsEntryTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.value,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IosTheme.spaceL,
            vertical: IosTheme.spaceM,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: IosTheme.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: IosType.callout),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: IosType.footnotePlus,
                          color: p.label2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: IosTheme.spaceS),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    value!,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: p.label2,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: IosTheme.spaceXS),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: p.label3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 二级设置页的分组：标题 + 白卡片，行之间自动补分隔线
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    final radius = BorderRadius.circular(IosTheme.radiusCard);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) IosSectionHeader(title: title!),
        // 卡片用 Material 承载背景：里面的 ListTile 需要最近的 Material
        // 祖先来画底色和墨水涟漪，用 Container(装饰盒) 会把涟漪吃掉。
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: IosTheme.shadowS,
          ),
          child: Material(
            color: p.surface,
            borderRadius: radius,
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
        ),
      ],
    );
  }
}

/// 二级设置页骨架：标题栏 + 可滚动内容
class SettingsSubPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSubPage({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceM,
        ),
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: IosTheme.spaceL),
            children[i],
          ],
          const SizedBox(height: IosTheme.spaceXXL),
        ],
      ),
    );
  }
}
