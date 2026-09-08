import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../utils/session_format.dart';

/// 对话页左侧会话抽屉：按 cwd 目录分组，可折叠/展开，平铺显示全部会话。
class SessionDrawer extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;

  /// 当前活动服务器 ID（未读标记 seenKey 前缀）
  final String serverId;
  final String? activeId;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCreateUngrouped;
  final void Function(String? cwd) onCreateInWorkspace;
  final void Function(String sessionId) onSelectSession;

  const SessionDrawer({
    super.key,
    required this.sessions,
    required this.serverId,
    required this.activeId,
    required this.loading,
    required this.onRefresh,
    required this.onCreateUngrouped,
    required this.onCreateInWorkspace,
    required this.onSelectSession,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '会话',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '刷新',
                      onPressed: onRefresh,
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建会话'),
              onTap: onCreateUngrouped,
            ),
            const Divider(height: 1),
            Expanded(
              child: sessions.isEmpty
                  ? const Center(child: Text('暂无会话'))
                  : Consumer<SettingsService>(
                      builder: (context, settings, _) => ListView(
                        children: _buildGroups(context, settings),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroups(BuildContext context, SettingsService settings) {
    final order = <String>[];
    final byCwd = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      final key = (s['cwd'] as String?) ?? '';
      byCwd.putIfAbsent(key, () => []).add(s);
      if (!order.contains(key)) order.add(key);
    }
    final groups = order.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return _latestOf(byCwd[b]!).compareTo(_latestOf(byCwd[a]!));
      });

    final widgets = <Widget>[];
    for (final cwd in groups) {
      final items = byCwd[cwd]!
        ..sort((a, b) => activityOf(b).compareTo(activityOf(a)));
      final expanded = !settings.collapsedWs.contains(cwd);
      widgets.add(ListTile(
        dense: true,
        leading: Icon(
          cwd.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
          size: 20,
        ),
        title: Text(
          cwd.isEmpty ? '未分组' : _dirLabel(cwd),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: cwd.isEmpty ? null : Text(cwd, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cwd.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: '在此目录新建会话',
                onPressed: () => onCreateInWorkspace(cwd),
              ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
            ),
          ],
        ),
        onTap: () => settings.setCollapsedWs(cwd, !expanded),
      ));
      if (expanded) {
        for (final s in items) {
          widgets.add(_SessionTile(
            session: s,
            serverId: serverId,
            activeId: activeId,
            indented: cwd.isNotEmpty,
            onSelect: onSelectSession,
          ));
        }
      }
      widgets.add(const Divider(height: 1));
    }
    if (widgets.isNotEmpty) widgets.removeLast();
    return widgets;
  }

  int _latestOf(List<Map<String, dynamic>> items) => items.isEmpty
      ? 0
      : items.map(activityOf).reduce((a, b) => a > b ? a : b);

  static String _dirLabel(String cwd) {
    final parts =
        cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? cwd : parts.last;
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final String serverId;
  final String? activeId;
  final bool indented;
  final void Function(String sessionId) onSelect;

  const _SessionTile({
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
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(
        left: indented ? 32 : 16,
        right: 16,
      ),
      selected: selected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.4),
      leading: Icon(
        running
            ? Icons.sync
            : (session['blank'] == true
                ? Icons.chat_bubble_outline
                : Icons.chat_bubble),
        size: 20,
      ),
      title: Text(
        sessionTitleOf(session),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        timeAgoOf(session['updatedAt'] as int?),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Consumer<SettingsService>(
        builder: (_, settings, __) => settings.unviewedIds
                .contains(settings.seenKey(serverId, id))
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
              )
            : const SizedBox.shrink(),
      ),
      onTap: () => onSelect(id),
    );
  }
}
