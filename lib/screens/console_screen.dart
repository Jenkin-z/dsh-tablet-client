import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_state.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../utils/constants.dart';
import '../utils/console_sessions.dart';
import '../widgets/connection_status.dart';
import '../widgets/console_devices.dart';
import '../widgets/console_recent_list.dart';
import '../widgets/console_widgets.dart';
import 'pair_screen.dart';

/// 控制台：顶部紧凑机器条，下方跨机器混排最近会话
///
/// 重构后：只做展示，不做权威判断。
/// 连接/会话状态一律从 SessionState 读取，不自己推断。
class ConsoleScreen extends StatelessWidget {
  final void Function(String serverId, String sessionId) onOpenSession;

  /// 只切机器、不指定会话。点设备条时走这条。
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
    return Consumer2<ServerManager, SettingsService>(
      builder: (context, manager, settings, _) {
        // 控制台只关心「当前会话」和「各会话待办类型」。
        // 用 Selector 把运行态/流式等高频通知挡在页面之外：
        // IndexedStack 里隐藏的控制台不会跟着聊天页一起重建。
        return Selector<SessionState, String>(
          selector: (_, session) {
            final pending = session.pendingSessionIds.toList()..sort();
            final kinds = pending
                .map((id) => '$id:${session.pendingKindOf(id)}')
                .join(',');
            return '${session.sessionId}|$kinds';
          },
          builder: (context, _, __) {
            final session = context.read<SessionState>();
            final groups = manager.groups;
            final p = IosPalette.of(context);
            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                title: Text(
                  '控制台',
                  style: TextStyle(
                    fontSize: IosType.title3,
                    fontWeight: FontWeight.w600,
                    color: p.label,
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
                            fontSize: IosType.footnotePlus,
                            color: p.label2,
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.refresh, size: 22, color: p.label2),
                    tooltip: '刷新',
                    onPressed: manager.refreshAll,
                  ),
                ],
              ),
              body: _body(context, manager, settings, session, groups),
            );
          },
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
    SessionState session,
    List<ServerGroup> groups,
  ) {
    if (groups.isEmpty) return _emptyState(context);

    // 用实际布局约束判断，而不是 MediaQuery：
    // 分屏/旋转时 MediaQuery 可能比布局晚一帧，横竖屏会闪回旧布局。
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        return isLandscape
            ? _landscapeBody(context, manager, settings, session, groups)
            : _portraitBody(context, manager, settings, session, groups);
      },
    );
  }

  /// 竖屏：保持原来的顶部设备条 + 下方最近会话。
  Widget _portraitBody(
    BuildContext context,
    ServerManager manager,
    SettingsService settings,
    SessionState session,
    List<ServerGroup> groups,
  ) {
    return RefreshIndicator(
      onRefresh: manager.refreshAll,
      child: ListView(
        padding: const EdgeInsets.only(bottom: IosTheme.spaceXXXL),
        children: [
          const SizedBox(height: IosTheme.spaceS),
          ConsoleDevices(
            groups: groups,
            // 高亮只看「哪台是当前机器」，与连没连上无关。
            activeServerId: settings.activeServerId,
            pendingCountOf: (serverId) =>
                _pendingCountOf(session, groups, serverId),
            onTapDevice: (serverId) => _onTapDevice(context, groups, serverId),
          ),
          const SizedBox(height: IosTheme.spaceS),
          _recentBlock(context, settings, session, groups),
        ],
      ),
    );
  }

  /// 横屏：设备切换固定在左侧竖栏，右侧只放会话列表。
  Widget _landscapeBody(
    BuildContext context,
    ServerManager manager,
    SettingsService settings,
    SessionState session,
    List<ServerGroup> groups,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _deviceRail(context, settings, session, groups),
        Expanded(
          child: RefreshIndicator(
            onRefresh: manager.refreshAll,
            child: ListView(
              padding: const EdgeInsets.only(bottom: IosTheme.spaceXXXL),
              children: [
                const SizedBox(height: IosTheme.spaceS),
                _recentBlock(context, settings, session, groups),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceRail(
    BuildContext context,
    SettingsService settings,
    SessionState session,
    List<ServerGroup> groups,
  ) {
    final p = IosPalette.of(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.separator)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConsoleSectionHeader(
              icon: Icons.devices_other,
              iconColor: p.accent,
              title: '设备',
              count: groups.length,
            ),
            Expanded(
              child: ConsoleDevices(
                groups: groups,
                activeServerId: settings.activeServerId,
                axis: Axis.vertical,
                pendingCountOf: (serverId) =>
                    _pendingCountOf(session, groups, serverId),
                onTapDevice: (serverId) =>
                    _onTapDevice(context, groups, serverId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 该机器上等待审批/提问的会话数（设备卡待办角标）
  ({int approvals, int questions}) _pendingCountOf(
    SessionState session,
    List<ServerGroup> groups,
    String serverId,
  ) {
    final group = groups.where((g) => g.server.id == serverId).firstOrNull;
    if (group == null) return (approvals: 0, questions: 0);
    var approvals = 0;
    var questions = 0;
    for (final s in group.monitor.sessions) {
      final id = s['sessionId'] as String? ?? '';
      if (id.isEmpty) continue;
      switch (session.pendingKindOf(id)) {
        case 'approval':
          approvals++;
        case 'question' || 'plan-review':
          questions++;
      }
    }
    return (approvals: approvals, questions: questions);
  }

  Widget _recentBlock(
    BuildContext context,
    SettingsService settings,
    SessionState session,
    List<ServerGroup> groups,
  ) {
    // 跨机器混排：所有机器 3 小时窗口内的会话放在同一张卡片里，
    // 按最近活动倒序；设备归属由每行的徽章表达。
    final recent = collectRecentSessions(groups, window: _window);
    final unviewedKeys = settings.unviewedIds;
    final hasUnviewed = unviewedKeys.isNotEmpty;
    // 标题旁的橙色徽标只表示「窗口内有未读」；「全部已读」则清全量，
    // 否则超窗的未读永远清不掉（顶部计数是全量的）。
    final hasRecentUnviewed = recent.any((entry) {
      final id = entry.session['sessionId'] as String? ?? '';
      return unviewedKeys.contains(settings.seenKey(entry.serverId, id));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsoleSectionHeader(
          icon: Icons.forum_outlined,
          iconColor: IosPalette.of(context).accent,
          title: '最近 3 小时',
          count: recent.length,
          badge: hasRecentUnviewed,
          action: hasUnviewed
              ? TextButton(
                  // 清「全部未读」，而不是只清这个 3 小时区块里的。
                  // 顶部未读计数是全量的，这里必须用同一个 scope。
                  onPressed: () => settings.markAllSeen(
                    settings.unviewedIds.toList(growable: false),
                  ),
                  child: Text(
                    '全部已读',
                    style: TextStyle(
                      color: IosPalette.of(context).accent,
                      fontSize: IosType.footnotePlus,
                    ),
                  ),
                )
              : null,
        ),
        ConsoleRecentList(
          entries: recent,
          currentSessionId: session.sessionId,
          activeServerId: settings.activeServerId,
          unviewedKeys: unviewedKeys,
          unviewedKeyBuilder: settings.seenKey,
          pendingKindOf: session.pendingKindOf,
          onOpenSession: onOpenSession,
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final p = IosPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.computer_outlined, size: 56, color: p.label3),
          const SizedBox(height: IosTheme.spaceM),
          Text(
            '还没有 PC',
            style: TextStyle(
              fontSize: IosType.title3,
              fontWeight: FontWeight.w600,
              color: p.label2,
            ),
          ),
          const SizedBox(height: IosTheme.spaceS),
          Text(
            '去设置里添加一台运行 DSH 的电脑',
            style: TextStyle(fontSize: IosType.body, color: p.label3),
          ),
          const SizedBox(height: IosTheme.spaceXL),
          IosButton(
            label: '添加 PC',
            icon: Icons.add,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 手势语义唯一：点设备条 = 只切当前机器，留在控制台。
  ///
  /// 曾经这里会「有运行会话就跳对话、否则不跳」，同一个动作两种结果，
  /// 用户感受就是「有点乱」。要看会话请点会话行 —— 那是另一个手势。
  void _onTapDevice(
    BuildContext context,
    List<ServerGroup> groups,
    String serverId,
  ) {
    final group = groups.where((g) => g.server.id == serverId).firstOrNull;
    if (group == null) return;
    if (group.server.unpaired) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PairScreen(existingServerId: serverId),
        ),
      );
      return;
    }
    onSwitchServer(serverId);
  }
}
