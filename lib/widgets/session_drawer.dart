import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../utils/session_format.dart';

String _dirLabel(String cwd) {
  final parts = cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? cwd : parts.last;
}

/// 对话页左侧会话抽屉：按 cwd 目录分组，可折叠/展开。
/// 默认全部收起；当前会话所在目录自动展开；展开后最多显示 5 条。
class SessionDrawer extends StatefulWidget {
  final List<Map<String, dynamic>> sessions;
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
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  final Map<String, bool> _groupShowAll = {};

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
                  if (widget.loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '刷新',
                      onPressed: widget.onRefresh,
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建会话'),
              onTap: widget.onCreateUngrouped,
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.sessions.isEmpty
                  ? const Center(child: Text('暂无会话'))
                  : Consumer<SettingsService>(
                      builder: (context, settings, _) => ListView(
                        children: _buildGroups(settings),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroups(SettingsService settings) {
    final currentCwd = _currentCwd();
    final order = <String>[];
    final byCwd = <String, List<Map<String, dynamic>>>{};
    for (final s in widget.sessions) {
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
      final expanded = settings.expandedWs.contains(cwd) ||
          (settings.expandedWs.isEmpty && cwd == (currentCwd ?? ''));
      widgets.add(_GroupHeader(
        cwd: cwd,
        isExpanded: expanded,
        onCreate: cwd.isEmpty ? null : () => widget.onCreateInWorkspace(cwd),
        onToggle: () => settings.setWsExpanded(cwd, !expanded),
      ));
      if (expanded) {
        final showAll = _groupShowAll[cwd] ?? false;
        final visibleCount =
            showAll ? items.length : (items.length > 5 ? 5 : items.length);
        for (var i = 0; i < visibleCount; i++) {
          widgets.add(_SessionTile(
            session: items[i],
            serverId: widget.serverId,
            activeId: widget.activeId,
            indented: cwd.isNotEmpty,
            onSelect: widget.onSelectSession,
          ));
        }
        if (items.length > 5) {
          widgets.add(_MoreTile(
            cwd: cwd,
            showAll: showAll,
            total: items.length,
            indented: cwd.isNotEmpty,
            onToggleShowAll: () {
              if (!mounted) return;
              setState(() {
                _groupShowAll[cwd] = !(_groupShowAll[cwd] ?? false);
              });
            },
          ));
        }
      }
      widgets.add(const Divider(height: 1));
    }
    if (widgets.isNotEmpty) widgets.removeLast();
    return widgets;
  }

  String? _currentCwd() {
    if (widget.activeId == null) return null;
    for (final s in widget.sessions) {
      if (s['sessionId'] == widget.activeId) {
        return s['cwd'] as String? ?? '';
      }
    }
    return null;
  }

  int _latestOf(List<Map<String, dynamic>> items) => items.isEmpty
      ? 0
      : items.map(activityOf).reduce((a, b) => a > b ? a : b);
}

class _GroupHeader extends StatelessWidget {
  final String cwd;
  final bool isExpanded;
  final VoidCallback? onCreate;
  final VoidCallback onToggle;

  const _GroupHeader({
    required this.cwd,
    required this.isExpanded,
    required this.onCreate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
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
          if (onCreate != null)
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: '在此目录新建会话',
              onPressed: onCreate,
            ),
          Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
          ),
        ],
      ),
      onTap: onToggle,
    );
  }
}

class _MoreTile extends StatelessWidget {
  final String cwd;
  final bool showAll;
  final int total;
  final bool indented;
  final VoidCallback onToggleShowAll;

  const _MoreTile({
    required this.cwd,
    required this.showAll,
    required this.total,
    required this.indented,
    required this.onToggleShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(
        left: indented ? 32 : 16,
        right: 16,
      ),
      title: Text(
        showAll ? '收起' : '显示全部 $total 条',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Icon(
        showAll ? Icons.expand_less : Icons.expand_more,
        size: 18,
      ),
      onTap: onToggleShowAll,
    );
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
