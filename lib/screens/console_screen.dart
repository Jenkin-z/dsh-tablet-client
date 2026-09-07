import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dsh_server.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../widgets/console_widgets.dart';
import 'pair_screen.dart';

/// 控制台：按 PC 分组，展示进行中 / 待查看 / 最近活跃
class ConsoleScreen extends StatelessWidget {
  final void Function(String serverId, String sessionId) onOpenSession;

  const ConsoleScreen({super.key, required this.onOpenSession});

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
      return const Center(child: Text('还没有 PC，去设置里扫码添加'));
    }
    final loading = groups.every((g) => g.monitor.loading) &&
        groups.every((g) => g.monitor.sessions.isEmpty);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: manager.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          ConsoleStatStrip(
            running: manager.runningCount,
            unviewed: manager.unviewedCount,
            total: manager.totalCount,
          ),
          for (final g in groups) ...[
            const SizedBox(height: 12),
            _PcHeader(group: g),
            if (g.server.unpaired)
              _PairHint(server: g.server)
            else if (g.monitor.error != null && g.monitor.sessions.isEmpty)
              ConsoleQuietLine(text: '离线：${g.monitor.error}')
            else
              _PcSessions(
                group: g,
                currentKey: settings.active == null
                    ? null
                    : settings.seenKey(
                        settings.active!.id, settings.sessionId ?? ''),
                onOpen: onOpenSession,
                onMarkAll: () => settings.markAllSeen(
                  g.unviewed.map((s) => settings.seenKey(
                      g.server.id, s['sessionId'] as String? ?? '')),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PcHeader extends StatelessWidget {
  final ServerGroup group;
  const _PcHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final online = group.monitor.online && !group.server.unpaired;
    return Row(
      children: [
        Icon(
          Icons.computer,
          size: 18,
          color: online ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            group.server.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          online ? group.server.host : (group.server.unpaired ? '需配对' : '离线'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PairHint extends StatelessWidget {
  final DshServer server;
  const _PairHint({required this.server});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('需要重新扫码配对'),
        subtitle: Text(server.lastError ?? server.host),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PairScreen(existingServerId: server.id),
          ),
        ),
      ),
    );
  }
}

class _PcSessions extends StatelessWidget {
  final ServerGroup group;
  final String? currentKey;
  final void Function(String serverId, String sessionId) onOpen;
  final VoidCallback onMarkAll;

  const _PcSessions({
    required this.group,
    required this.currentKey,
    required this.onOpen,
    required this.onMarkAll,
  });

  @override
  Widget build(BuildContext context) {
    final sid = group.server.id;
    final running = group.running;
    final unviewed = group.unviewed;
    final recent = group.recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsoleSectionHeader(
          icon: Icons.sync,
          iconColor: Colors.green,
          title: '进行中',
          count: running.length,
        ),
        if (running.isEmpty)
          const ConsoleQuietLine(text: '暂无运行中的会话')
        else
          for (var i = 0; i < running.length; i++)
            ConsoleEntrance(
              key: ValueKey('run:$sid:${running[i]['sessionId']}'),
              index: i,
              child: ConsoleRunningCard(
                session: running[i],
                workspaces: group.monitor.workspaces,
                isCurrent:
                    currentKey == '$sid::${running[i]['sessionId']}',
                onTap: () => onOpen(sid, running[i]['sessionId'] as String),
              ),
            ),
        ConsoleSectionHeader(
          icon: Icons.mark_as_unread_outlined,
          iconColor: Colors.orange,
          title: '待查看',
          count: unviewed.length,
          badge: unviewed.isNotEmpty,
          action: unviewed.isEmpty
              ? null
              : TextButton(onPressed: onMarkAll, child: const Text('全部已读')),
        ),
        if (unviewed.isEmpty)
          const ConsoleQuietLine(text: '没有未查看的完成会话')
        else
          for (var i = 0; i < unviewed.length; i++)
            ConsoleEntrance(
              key: ValueKey('unv:$sid:${unviewed[i]['sessionId']}'),
              index: i,
              child: ConsoleUnviewedCard(
                session: unviewed[i],
                workspaces: group.monitor.workspaces,
                onTap: () => onOpen(sid, unviewed[i]['sessionId'] as String),
              ),
            ),
        ConsoleSectionHeader(
          icon: Icons.history,
          iconColor: Colors.blueGrey,
          title: '最近活跃',
          count: recent.length,
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (recent.isEmpty)
                const ListTile(
                  dense: true,
                  title: Text('暂无', textAlign: TextAlign.center),
                )
              else
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ConsoleRecentTile(
                    session: recent[i],
                    workspaces: group.monitor.workspaces,
                    isCurrent:
                        currentKey == '$sid::${recent[i]['sessionId']}',
                    onTap: () =>
                        onOpen(sid, recent[i]['sessionId'] as String),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
