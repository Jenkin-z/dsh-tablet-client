import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../utils/session_format.dart';

const ungroupedWorkspaceKey = '_ungrouped';

/// 对话页左侧会话抽屉：按工作区分组，组内按活跃时间倒序。
class SessionDrawer extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> workspaces;
  final Set<String> archivedIds;
  final String? activeId;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCreateUngrouped;
  final void Function(String workspaceId) onCreateInWorkspace;
  final void Function(String sessionId) onSelectSession;

  const SessionDrawer({
    super.key,
    required this.sessions,
    required this.workspaces,
    required this.archivedIds,
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
    final byId = <String, Map<String, dynamic>>{
      for (final s in sessions) (s['sessionId'] as String? ?? ''): s,
    };
    final widgets = <Widget>[];
    final grouped = <String>{};

    for (final w in workspaces) {
      final wsId = w['workspaceId'] as String? ?? '';
      final title = (w['title'] as String?)?.trim();
      final path = w['path'] as String? ?? '';
      final ids = (w['sessionIds'] as List<dynamic>? ?? []).whereType<String>();
      final visible = ids
          .where((id) => byId.containsKey(id) && !archivedIds.contains(id))
          .toList()
        ..sort((a, b) =>
            activityOf(byId[b]!).compareTo(activityOf(byId[a]!)));
      if (visible.isEmpty) continue;
      grouped.addAll(visible);
      final expanded = settings.expandedWs.contains(wsId);
      widgets.add(
        ListTile(
          dense: true,
          leading: Icon(
            expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
            size: 20,
          ),
          title: Text(
            (title == null || title.isEmpty) ? path : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: (title != null && title.isNotEmpty)
              ? Text(path, maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: '在此工作区新建会话',
                onPressed: () => onCreateInWorkspace(wsId),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
            ],
          ),
          onTap: () => settings.setWsExpanded(wsId, !expanded),
        ),
      );
      if (!expanded) continue;
      for (final id in visible) {
        widgets.add(_SessionTile(
          session: byId[id]!,
          activeId: activeId,
          indented: true,
          onSelect: onSelectSession,
        ));
      }
    }

    final ungrouped = byId.keys
        .where((id) =>
            id.isNotEmpty &&
            !grouped.contains(id) &&
            !archivedIds.contains(id))
        .toList()
      ..sort((a, b) =>
          activityOf(byId[b]!).compareTo(activityOf(byId[a]!)));
    if (ungrouped.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
      final expanded = settings.expandedWs.contains(ungroupedWorkspaceKey);
      widgets.add(
        ListTile(
          dense: true,
          leading: const Icon(Icons.inbox_outlined, size: 20),
          title: const Text(
            '未分组',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
          ),
          onTap: () =>
              settings.setWsExpanded(ungroupedWorkspaceKey, !expanded),
        ),
      );
      if (expanded) {
        for (final id in ungrouped) {
          widgets.add(_SessionTile(
            session: byId[id]!,
            activeId: activeId,
            indented: true,
            onSelect: onSelectSession,
          ));
        }
      }
    }
    return widgets;
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final String? activeId;
  final bool indented;
  final void Function(String sessionId) onSelect;

  const _SessionTile({
    required this.session,
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
        builder: (_, settings, __) => settings.unviewedIds.contains(id)
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
