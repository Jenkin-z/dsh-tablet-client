import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../utils/session_format.dart';

String dirLabel(String cwd) {
  final parts = cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? cwd : parts.last;
}

/// 会话分组头部 —— iOS 风格
///
/// 目录名 + 展开/收起 + 新建按钮。
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

/// 单个会话条目 —— iOS 风格
class SessionListTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final String serverId;
  final String? activeId;
  final bool indented;
  final void Function(String sessionId) onSelect;

  const SessionListTile({
    super.key,
    required this.session,
    required this.serverId,
    required this.activeId,
    required this.indented,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final id = session['sessionId'] as String? ?? '';
    final selected = id == activeId;
    final running = session['running'] == true;
    return Material(
      color: selected
          ? IosTheme.iosBlue.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(id),
        child: Padding(
          padding: EdgeInsets.only(
            left: indented ? IosTheme.spaceXXXL : IosTheme.spaceL,
            right: IosTheme.spaceL,
            top: IosTheme.spaceS,
            bottom: IosTheme.spaceS,
          ),
          child: Row(
            children: [
              Icon(
                running
                    ? Icons.sync
                    : (session['blank'] == true
                        ? Icons.chat_bubble_outline
                        : Icons.chat_bubble),
                size: 20,
                color: running
                    ? IosTheme.iosGreen
                    : (selected ? IosTheme.iosBlue : IosTheme.iosGray),
              ),
              const SizedBox(width: IosTheme.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionTitleOf(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected || running ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    Text(
                      timeAgoOf(session['updatedAt'] as int?),
                      style: TextStyle(
                        fontSize: 13,
                        color: IosTheme.iosGray,
                      ),
                    ),
                  ],
                ),
              ),
              Consumer<SettingsService>(
                builder: (_, settings, __) => settings.unviewedIds
                        .contains(settings.seenKey(serverId, id))
                    ? IosBadge(showDot: true)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
