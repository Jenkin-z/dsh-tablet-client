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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    if (entries.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        padding: const EdgeInsets.all(IosTheme.spaceXL),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        ),
        child: const Center(
          child: Text(
            '最近 3 小时没有活跃会话',
            style: TextStyle(color: IosTheme.iosGray, fontSize: 15),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        boxShadow: IosTheme.shadowS,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 56,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
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
