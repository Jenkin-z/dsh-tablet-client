import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_monitor.dart';
import '../services/settings_service.dart';
import '../widgets/console_widgets.dart';

/// 控制台：进行中的对话 + 完成后未查看的对话 + 最近活跃
class ConsoleScreen extends StatefulWidget {
  final void Function(String sessionId) onOpenSession;

  const ConsoleScreen({super.key, required this.onOpenSession});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<SessionMonitor, SettingsService>(
      builder: (context, monitor, settings, _) {
        final running = monitor.runningSessions;
        final unviewed = monitor.unviewedSessions;
        final recent = monitor.recentSessions;
        return Scaffold(
          appBar: AppBar(
            title: const Text('控制台'),
            actions: [
              if (monitor.lastRefresh != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '更新于 ${_clock(monitor.lastRefresh!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: monitor.refresh,
              ),
            ],
          ),
          body: _buildBody(monitor, settings, running, unviewed, recent),
        );
      },
    );
  }

  String _clock(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  Widget _buildBody(
    SessionMonitor monitor,
    SettingsService settings,
    List<Map<String, dynamic>> running,
    List<Map<String, dynamic>> unviewed,
    List<Map<String, dynamic>> recent,
  ) {
    if (monitor.loading && monitor.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (monitor.error != null && monitor.sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('加载失败：${monitor.error}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: monitor.refresh,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final allQuiet = running.isEmpty && unviewed.isEmpty;
    return RefreshIndicator(
      onRefresh: monitor.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          ConsoleStatStrip(
            running: running.length,
            unviewed: unviewed.length,
            total: monitor.sessions.length,
          ),
          const SizedBox(height: 8),
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
                key: ValueKey('run:${running[i]['sessionId']}'),
                index: i,
                child: ConsoleRunningCard(
                  session: running[i],
                  workspaces: monitor.workspaces,
                  isCurrent: running[i]['sessionId'] == settings.sessionId,
                  onTap: () =>
                      widget.onOpenSession(running[i]['sessionId'] as String),
                ),
              ),
          const SizedBox(height: 8),
          ConsoleSectionHeader(
            icon: Icons.mark_as_unread_outlined,
            iconColor: Colors.orange,
            title: '待查看',
            count: unviewed.length,
            badge: unviewed.isNotEmpty,
            action: unviewed.isEmpty
                ? null
                : TextButton(
                    onPressed: () => settings.markAllSeen(
                      unviewed.map((s) => s['sessionId'] as String? ?? ''),
                    ),
                    child: const Text('全部已读'),
                  ),
          ),
          if (unviewed.isEmpty)
            const ConsoleQuietLine(text: '没有未查看的完成会话')
          else
            for (var i = 0; i < unviewed.length; i++)
              ConsoleEntrance(
                key: ValueKey('unv:${unviewed[i]['sessionId']}'),
                index: i,
                child: ConsoleUnviewedCard(
                  session: unviewed[i],
                  workspaces: monitor.workspaces,
                  onTap: () =>
                      widget.onOpenSession(unviewed[i]['sessionId'] as String),
                ),
              ),
          const SizedBox(height: 8),
          ConsoleSectionHeader(
            icon: Icons.history,
            iconColor: Colors.blueGrey,
            title: '最近活跃',
            count: recent.length,
          ),
          if (recent.isEmpty && allQuiet)
            const ConsoleEmptyState()
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ConsoleRecentTile(
                      session: recent[i],
                      workspaces: monitor.workspaces,
                      isCurrent: recent[i]['sessionId'] == settings.sessionId,
                      onTap: () => widget
                          .onOpenSession(recent[i]['sessionId'] as String),
                    ),
                  ],
                  if (recent.isEmpty)
                    const ListTile(
                      dense: true,
                      title: Text('暂无', textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
