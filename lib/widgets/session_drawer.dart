import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../utils/session_format.dart';
import 'session_tile.dart';

/// 对话页左侧会话抽屉 —— iOS 风格
///
/// 按 cwd 目录分组，可折叠/展开。
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosTheme.spaceXL,
                IosTheme.spaceL,
                IosTheme.spaceL,
                IosTheme.spaceS,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '会话',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (widget.loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: IosTheme.iosBlue,
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        size: 22,
                        color: IosTheme.iosBlue,
                      ),
                      tooltip: '刷新',
                      onPressed: widget.onRefresh,
                    ),
                ],
              ),
            ),
            // 新建会话按钮
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceL,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: IosTheme.iosBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(IosTheme.radiusS),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline,
                    color: IosTheme.iosBlue,
                    size: 22,
                  ),
                  title: const Text(
                    '新建会话',
                    style: TextStyle(
                      color: IosTheme.iosBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: widget.onCreateUngrouped,
                ),
              ),
            ),
            const SizedBox(height: IosTheme.spaceM),
            // 分隔线
            Container(
              height: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            // 会话列表
            Expanded(
              child: widget.sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: IosTheme.iosGray3,
                          ),
                          const SizedBox(height: IosTheme.spaceM),
                          Text(
                            '暂无会话',
                            style: TextStyle(
                              fontSize: 16,
                              color: IosTheme.iosGray,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Consumer<SettingsService>(
                      builder: (context, settings, _) => ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: IosTheme.spaceS,
                        ),
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
      widgets.add(SessionGroupHeader(
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
          widgets.add(SessionListTile(
            session: items[i],
            serverId: widget.serverId,
            activeId: widget.activeId,
            indented: cwd.isNotEmpty,
            onSelect: widget.onSelectSession,
          ));
        }
        if (items.length > 5) {
          widgets.add(SessionMoreTile(
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
      widgets.add(
        Container(
          height: 0.5,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          margin: const EdgeInsets.only(left: IosTheme.spaceL),
        ),
      );
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
