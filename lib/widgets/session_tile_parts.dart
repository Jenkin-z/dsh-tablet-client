import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 会话分组头部 —— iOS 风格
///
/// 目录名 + 展开/收起 + 新建按钮。
/// 从 session_tile.dart 拆出来，让那个文件守住 200 行上限。
class SessionGroupHeader extends StatelessWidget {
  final String cwd;
  final bool isExpanded;
  final VoidCallback? onCreate;
  final VoidCallback onToggle;

  const SessionGroupHeader({
    super.key,
    required this.cwd,
    required this.isExpanded,
    required this.onCreate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IosTheme.spaceL,
            vertical: IosTheme.spaceM,
          ),
          child: Row(
            children: [
              Icon(
                cwd.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
                size: 20,
                color: IosTheme.iosBlue,
              ),
              const SizedBox(width: IosTheme.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cwd.isEmpty ? '未分组' : dirLabel(cwd),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (cwd.isNotEmpty)
                      Text(
                        cwd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: IosTheme.iosGray,
                        ),
                      ),
                  ],
                ),
              ),
              if (onCreate != null)
                IconButton(
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                    color: IosTheme.iosBlue,
                  ),
                  tooltip: '在此目录新建会话',
                  onPressed: onCreate,
                ),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: IosTheme.iosGray3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「显示全部 / 收起」按钮 —— iOS 风格
/// 从 session_tile.dart 拆出来，让那个文件守住 200 行上限。
class SessionMoreTile extends StatelessWidget {
  final bool showAll;
  final int total;
  final bool indented;
  final VoidCallback onToggleShowAll;

  const SessionMoreTile({
    super.key,
    required this.showAll,
    required this.total,
    required this.indented,
    required this.onToggleShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggleShowAll,
        child: Padding(
          padding: EdgeInsets.only(
            left: indented ? IosTheme.spaceXXXL : IosTheme.spaceL,
            right: IosTheme.spaceL,
            top: IosTheme.spaceS,
            bottom: IosTheme.spaceS,
          ),
          child: Row(
            children: [
              Text(
                showAll ? '收起' : '显示全部 $total 条',
                style: const TextStyle(
                  fontSize: 14,
                  color: IosTheme.iosBlue,
                ),
              ),
              const SizedBox(width: IosTheme.spaceXS),
              Icon(
                showAll ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: IosTheme.iosBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目录名（取路径最后一段）
///
/// 从 session_tile.dart 拆出来，让那个文件守住 200 行上限。
String dirLabel(String cwd) {
  final parts = cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? cwd : parts.last;
}
