import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../utils/session_format.dart';

/// 对话页左侧会话抽屉：按 cwd 目录分组，可折叠/展开。
/// 默认全部收起；当前会话所在目录自动展开；每组最多先显示 5 条。
class SessionDrawer extends StatelessWidget {
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
    // 计算当前会话所在目录（用于默认展开）
    String? currentCwd;
    if (activeId != null) {
      for (final s in sessions) {
        if (s['sessionId'] == activeId) {
          currentCwd = s['cwd'] as String? ?? '';
          break;
        }
      }
    }

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
      // collapsedWs 为空 = 默认状态：只展开当前会话所在目录
      final isExpanded = settings.collapsedWs.isEmpty
          ? cwd == (currentCwd ?? '')
          : !settings.collapsedWs.contains(cwd);
      widgets.add(_GroupHeader(
        cwd: cwd,
        isExpanded: isExpanded,
        onCreate: cwd.isEmpty ? null : () => onCreateInWorkspace(cwd),
        onToggle: () => settings.setCollapsedWs(cwd, !isExpanded),
      ));
      if (isExpanded) {
        final visible = items.take(5).toList();
        for (final s in visible) {
          widgets.add(_SessionTile(
            session: s,
            serverId: serverId,
            activeId: activeId,
            indented: cwd.isNotEmpty,
            onSelect: onSelectSession,
          ));
        }
        if (items.length > 5) {
          widgets.add(StatefulBuilder(
            builder: (context, setLocal) {
              bool showAll = false;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(
                  left: cwd.isEmpty ? 16 : 32,
                  right: 16,
                ),
                title: Text(
                  _groupLabel(items.length, showAll),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.expand_more, size: 18),
                onTap: () => setLocal(() => showAll = !showAll),
              );
            },
          ));
        }
      }
      widgets.add(const Divider(height: 1));
    }
    if (widgets.isNotEmpty) widgets.removeLast();
    return widgets;
  }

  String _groupLabel(int total, bool expanded) =>
      expanded ? '收起' : '显示全部 $total 条';

  int _latestOf(List<Map<String, dynamic>> items) => items.isEmpty
      ? 0
      : items.map(activityOf).reduce((a, b) => a > b ? a : b);

  static String _dirLabel(String cwd) {
    final parts =
        cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? cwd : parts.last;
  }
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
        cwd.isEmpty ? '未分组' : SessionDrawer._dirLabel(cwd),
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
