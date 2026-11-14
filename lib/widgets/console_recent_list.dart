import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import '../utils/console_sessions.dart';
import 'console_session_tile.dart';

/// 最近 3 小时：跨机器混排的会话卡片
///
/// 不再按机器分段，每行自带设备徽章；条目已由
/// [collectRecentSessions] 过滤、去重并按时间倒序。
class ConsoleRecentList extends StatelessWidget {
  final List<ConsoleSessionEntry> entries;
  final String? currentSessionId;
  final String? activeServerId;
  final Set<String> unviewedKeys;
  final String Function(String serverId, String sessionId) unviewedKeyBuilder;
  final String? Function(String sessionId)? pendingKindOf;
  final void Function(String serverId, String sessionId) onOpenSession;

  const ConsoleRecentList({
    super.key,
    required this.entries,
    required this.unviewedKeys,
    required this.unviewedKeyBuilder,
    required this.onOpenSession,
    this.currentSessionId,
    this.activeServerId,
    this.pendingKindOf,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);

    if (entries.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        padding: const EdgeInsets.all(IosTheme.spaceXL),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(IosTheme.radiusCard),
          border: p.isDark ? Border.all(color: p.separator, width: 0.5) : null,
          boxShadow: p.isDark ? null : IosTheme.shadowM,
        ),
        child: Center(
          child: Text(
            '最近 3 小时没有活跃会话',
            style: TextStyle(color: p.label3, fontSize: IosType.body),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        border: p.isDark ? Border.all(color: p.separator, width: 0.5) : null,
        boxShadow: p.isDark ? null : IosTheme.shadowM,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 24,
                color: p.separator,
              ),
            ConsoleSessionTile(
              entry: entries[i],
              currentSessionId: currentSessionId,
              isActiveServer: entries[i].serverId == activeServerId,
              pendingKindOf: pendingKindOf,
              unviewedKeys: unviewedKeys,
              unviewedKeyBuilder: unviewedKeyBuilder,
              onOpenSession: onOpenSession,
            ),
          ],
        ],
      ),
    );
  }
}
