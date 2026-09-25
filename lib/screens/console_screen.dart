import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dsh_session_state.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../utils/constants.dart';
import '../widgets/connection_status.dart';
import '../widgets/console_devices.dart';
import '../widgets/console_merged_tile.dart';
import '../widgets/console_widgets.dart';
import 'pair_screen.dart';

/// 控制台：顶部每设备一张状态卡，下方按设备分组展示会话
///
/// 重构后：只做展示，不做权威判断。
/// 连接/会话状态一律从 DshSessionState 读取，不自己推断。
class ConsoleScreen extends StatelessWidget {
  final void Function(String serverId, String sessionId) onOpenSession;

  /// 只切机器、不指定会话。点设备卡但没有运行中的会话时走这条。
  final void Function(String serverId) onSwitchServer;

  const ConsoleScreen({
    super.key,
    required this.onOpenSession,
    required this.onSwitchServer,
  });

  /// 会话活跃窗口：与重构前的控制台一致（3 小时）
  static const _window = consoleRecentWindow;

  @override
  Widget build(BuildContext context) {
    return Consumer3<ServerManager, SettingsService, DshSessionState>(
      builder: (context, manager, settings, session, _) {
        final groups = manager.groups;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF000000) : IosTheme.iosGroupedBg,
          appBar: AppBar(
            title: const Text(
              '控制台',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              const Center(child: ConnectionStatus()),
              const SizedBox(width: IosTheme.spaceM),
              if (manager.lastRefresh != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: IosTheme.spaceS),
                    child: Text(
                      '更新于 ${_clock(manager.lastRefresh!)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: IosTheme.iosGray,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 22),
                tooltip: '刷新',
                onPressed: manager.refreshAll,
              ),
            ],
          ),
          body: _body(context, manager, settings, session, groups),
        );
      },
    );
  }

  String _clock(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  Widget _body(
    BuildContext context,
    ServerManager manager,
    SettingsService settings,
    DshSessionState session,
    List<ServerGroup> groups,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.computer_outlined,
              size: 56,
              color: IosTheme.iosGray,
            ),
            const SizedBox(height: IosTheme.spaceM),
            Text(
              '还没有 PC',
              style: TextStyle(
                fontSize: 17,
                color: IosTheme.iosGray,
              ),
            ),
            const SizedBox(height: IosTheme.spaceS),
            Text(
              '去设置里添加一台运行 DSH 的电脑',
              style: TextStyle(
                fontSize: 15,
                color: IosTheme.iosGray,
              ),
            ),
            const SizedBox(height: IosTheme.spaceXL),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PairScreen()),
                );
              },
              child: const Text('添加 PC'),
            ),
          ],
        ),
      );
    }

    // 3 小时窗口内的会话总数，用于区块标题的计数与「全部已读」
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _window.inMilliseconds;
    final activeKeys = <String>[];
    for (final g in groups) {
      for (final s in [...g.running, ...g.unviewed, ...g.recent]) {
        final id = s['sessionId'] as String? ?? '';
        if (id.isEmpty || s['blank'] == true) continue;
        if (((s['updatedAt'] as num?)?.toInt() ?? 0) < cutoff) continue;
        activeKeys.add(settings.seenKey(g.server.id, id));
      }
    }
    final unviewedKeys =
        activeKeys.where(settings.unviewedIds.contains).toSet();

    // 每台机器是否有窗口内的会话，没有就不渲染该分组（避免空标题）
    final groupsWithRecent = groups.where((g) {
      final c = DateTime.now().millisecondsSinceEpoch - _window.inMilliseconds;
      return [...g.running, ...g.unviewed, ...g.recent].any((s) {
        final id = s['sessionId'] as String? ?? '';
        if (id.isEmpty || s['blank'] == true) return false;
        return ((s['updatedAt'] as num?)?.toInt() ?? 0) >= c;
      });
    }).toList();

    return RefreshIndicator(
      onRefresh: manager.refreshAll,
      child: ListView(
        padding: const EdgeInsets.only(bottom: IosTheme.spaceXXXL),
        children: [
          ConsoleDevices(
            groups: groups,
            // 高亮只看「哪台是当前机器」，与连没连上无关。
            // 之前写成 session.connected ? activeServerId : null，
            // 一断线就全不亮，看着像切换没生效。
            activeServerId: settings.activeServerId,
            onTapDevice: (serverId) {
              // 点设备 = 切到这台机器（重构前就是直接 setActiveServer）。
              // 未配对先引导去配对；有运行中的会话就顺带进去。
              final group =
                  groups.where((g) => g.server.id == serverId).firstOrNull;
              if (group == null) return;
              if (group.server.unpaired) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PairScreen(existingServerId: serverId),
                  ),
                );
                return;
              }
              if (group.running.isNotEmpty) {
                onOpenSession(
                    serverId, group.running.first['sessionId'] as String);
              } else {
                onSwitchServer(serverId);
              }
            },
          ),
          const SizedBox(height: IosTheme.spaceL),
          ConsoleSectionHeader(
            icon: Icons.forum_outlined,
            iconColor: IosTheme.iosBlue,
            title: '最近 3 小时',
            count: activeKeys.length,
            badge: unviewedKeys.isNotEmpty,
            action: unviewedKeys.isEmpty
                ? null
                : TextButton(
                    onPressed: () => settings
                        .markAllSeen(unviewedKeys.toList(growable: false)),
                    child: const Text('全部已读'),
                  ),
          ),
          if (groupsWithRecent.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
              padding: const EdgeInsets.all(IosTheme.spaceXL),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(IosTheme.radiusCard),
              ),
              child: const Center(
                child: Text(
                  '最近 3 小时没有活跃会话',
                  style: TextStyle(color: IosTheme.iosGray, fontSize: 15),
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(IosTheme.radiusCard),
                boxShadow: IosTheme.shadowS,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < groupsWithRecent.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        indent: 56,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ConsoleMergedTile(
                      group: groupsWithRecent[i],
                      window: _window,
                      currentSessionId: session.sessionId,
                      pendingKindOf: session.pendingKindOf,
                      unviewedKeys: settings.unviewedIds,
                      unviewedKeyBuilder: settings.seenKey,
                      onOpenSession: (sessionId) =>
                          onOpenSession(groupsWithRecent[i].server.id, sessionId),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}