import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dsh_server.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../widgets/console_devices.dart';
import '../widgets/console_widgets.dart';
import 'pair_screen.dart';

/// 控制台：顶部每设备一张状态卡，下方合并会话列表（最近 3 小时活跃）
class ConsoleScreen extends StatelessWidget {
  final void Function(String serverId, String sessionId) onOpenSession;

  const ConsoleScreen({super.key, required this.onOpenSession});

  static const _window = Duration(hours: 3);

  @override
  Widget build(BuildContext context) {
    return Consumer2<ServerManager, SettingsService>(
      builder: (context, manager, settings, _) {
        final groups = manager.groups;
        return Scaffold(
          appBar: AppBar(
            title: const Text('控制台'),
            actions: [
              if (manager.lastRefresh != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '更新于 ${_clock(manager.lastRefresh!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: manager.refreshAll,
              ),
            ],
          ),
          body: _body(context, manager, settings, groups),
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
    List<ServerGroup> groups,
  ) {
    if (groups.isEmpty) {
      return const Center(child: Text('还没有 PC，去设置里添加'));
    }
    final loading = groups.every((g) => g.monitor.loading) &&
        groups.every((g) => g.monitor.sessions.isEmpty);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final merged = _mergedRecent(groups);
    final currentKey = settings.active == null
        ? null
        : settings.seenKey(settings.active!.id, settings.sessionId ?? '');
    final unviewedKeys = merged
        .where((m) =>
            settings.unviewedIds.contains(
                settings.seenKey(m.group.server.id, m.sessionIdAsString)))
        .map((m) =>
            settings.seenKey(m.group.server.id, m.sessionIdAsString))
        .toSet();
    return RefreshIndicator(
      onRefresh: manager.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _DeviceCards(
            groups: groups,
            activeId: settings.activeServerId,
            onSelect: (server) async {
              if (server.unpaired) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PairScreen(existingServerId: server.id),
                ));
                return;
              }
              await settings.setActiveServer(server.id);
            },
          ),
          const SizedBox(height: 12),
          ConsoleSectionHeader(
            icon: Icons.forum_outlined,
            iconColor: Colors.blueGrey,
            title: '最近 3 小时',
            count: merged.length,
            badge: unviewedKeys.isNotEmpty,
            action: unviewedKeys.isEmpty
                ? null
                : TextButton(
                    onPressed: () => settings.markAllSeen(
                        unviewedKeys.toList(growable: false)),
                    child: const Text('全部已读'),
                  ),
          ),
          if (merged.isEmpty)
            const Card(
              child: ListTile(
                dense: true,
                title: Text('最近 3 小时没有活跃会话',
                    textAlign: TextAlign.center),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < merged.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ConsoleMergedTile(
                      key: ValueKey(
                          '${merged[i].group.server.id}::${merged[i].sessionIdAsString}'),
                      session: merged[i].session,
                      deviceName: merged[i].group.server.name,
                      deviceOnline:
                          merged[i].group.monitor.online &&
                              !merged[i].group.server.unpaired,
                      isCurrent: currentKey ==
                          '${merged[i].group.server.id}::${merged[i].sessionIdAsString}',
                      isUnviewed: unviewedKeys.contains(settings.seenKey(
                          merged[i].group.server.id,
                          merged[i].sessionIdAsString)),
                      onTap: () => onOpenSession(merged[i].group.server.id,
                          merged[i].sessionIdAsString),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 合并所有设备的会话，仅保留最近 3 小时活跃的，按最近活动排序
  List<_MergedSession> _mergedRecent(List<ServerGroup> groups) {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _window.inMilliseconds;
    final out = <_MergedSession>[];
    for (final g in groups) {
      if (g.server.unpaired) continue;
      for (final s in g.monitor.sessions) {
        final id = s['sessionId'] as String? ?? '';
        if (id.isEmpty || s['blank'] == true) continue;
        if (g.monitor.archivedIds.contains(id)) continue;
        final updatedAt = (s['updatedAt'] as num?)?.toInt() ?? 0;
        if (updatedAt < cutoff) continue;
        out.add(_MergedSession(group: g, session: s));
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }
}

class _MergedSession {
  final ServerGroup group;
  final Map<String, dynamic> session;
  int get updatedAt => (session['updatedAt'] as num?)?.toInt() ?? 0;
  String get sessionIdAsString => session['sessionId'] as String? ?? '';
  const _MergedSession({required this.group, required this.session});
}

/// 顶部设备卡区：按宽度自适应列数
class _DeviceCards extends StatelessWidget {
  final List<ServerGroup> groups;
  final String? activeId;
  final void Function(DshServer server) onSelect;

  const _DeviceCards({
    required this.groups,
    required this.activeId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final cols = (cons.maxWidth / 240).floor().clamp(1, 4);
        final cardW = (cons.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in groups)
              SizedBox(
                width: cardW,
                child: ConsoleDeviceCard(
                  name: g.server.name,
                  hostLabel: '${g.server.host}:${g.server.port}',
                  online: g.monitor.online,
                  needsAuth: g.server.unpaired,
                  running: g.running.length,
                  unviewed: g.unviewed.length,
                  error: g.monitor.error,
                  active: activeId == g.server.id,
                  onTap: () => onSelect(g.server),
                ),
              ),
          ],
        );
      },
    );
  }
}
