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
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Scaffold(
              backgroundColor:
                  isDark ? const Color(0xFF000000) : IosTheme.iosGroupedBg,
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
            onTapDevice: (serverId) => _onTapDevice(context, groups, serverId),
          ),
          const SizedBox(height: IosTheme.spaceS),
          _recentBlock(settings, session, groups),
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
        _deviceRail(context, settings, groups),
        Expanded(
          child: RefreshIndicator(
            onRefresh: manager.refreshAll,
            child: ListView(
              padding: const EdgeInsets.only(bottom: IosTheme.spaceXXXL),
              children: [
                const SizedBox(height: IosTheme.spaceS),
                _recentBlock(settings, session, groups),
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
    List<ServerGroup> groups,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C0C0D) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
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
              iconColor: IosTheme.iosBlue,
              title: '设备',
              count: groups.length,
            ),
            Expanded(
              child: ConsoleDevices(
                groups: groups,
                activeServerId: settings.activeServerId,
                axis: Axis.vertical,
                onTapDevice: (serverId) =>
                    _onTapDevice(context, groups, serverId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentBlock(
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
          iconColor: IosTheme.iosBlue,
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
                  child: const Text('全部已读'),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.computer_outlined,
            size: 56,
            color: IosTheme.iosGray,
          ),
          const SizedBox(height: IosTheme.spaceM),
          const Text(
            '还没有 PC',
            style: TextStyle(fontSize: 17, color: IosTheme.iosGray),
          ),
          const SizedBox(height: IosTheme.spaceS),
          const Text(
            '去设置里添加一台运行 DSH 的电脑',
            style: TextStyle(fontSize: 15, color: IosTheme.iosGray),
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
