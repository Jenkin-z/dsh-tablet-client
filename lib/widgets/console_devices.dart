import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../theme/ios_theme.dart';
import 'console_machine_card.dart';

/// 顶部机器选择条：横向滚动的设备卡
///
/// 设备卡 = 状态点 + 机器名 + 后端徽标 + 心跳刻度 + 待办角标。
/// 点击只切当前机器，不按有没有运行中的会话分叉。
class ConsoleDevices extends StatelessWidget {
  final List<ServerGroup> groups;
  final void Function(String serverId) onTapDevice;

  /// 当前正在对话的 PC（来自权威状态源），null 表示未连接
  final String? activeServerId;

  /// 该机器上等待审批/提问的会话数（待办角标）
  final ({int approvals, int questions}) Function(String serverId)
      pendingCountOf;

  /// 竖屏用横向卡片条，横屏用左侧纵向列表
  final Axis axis;

  const ConsoleDevices({
    super.key,
    required this.groups,
    required this.onTapDevice,
    required this.pendingCountOf,
    this.activeServerId,
    this.axis = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    if (axis == Axis.vertical) {
      return ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceS,
        ),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: IosTheme.spaceS),
        // 侧边栏：卡片充满整行宽度（2026-11 反馈：横屏设备卡没充满侧边栏）
        itemBuilder: (context, i) => _card(context, i, expand: true),
      );
    }

    return SizedBox(
      height: ConsoleMachineCard.cardHeight + IosTheme.spaceS * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: IosTheme.spaceS),
        itemBuilder: _card,
      ),
    );
  }

  Widget _card(BuildContext context, int i, {bool expand = false}) {
    final group = groups[i];
    final name = group.server.name;
    final host = group.server.host;
    final pending = pendingCountOf(group.server.id);
    return ConsoleMachineCard(
      // 别名优先，空名退回地址（防御旧数据）
      title: name.isNotEmpty ? name : (host.isNotEmpty ? host : 'PC'),
      kind: group.server.kind,
      beats: group.monitor.heartbeat,
      online: group.monitor.online,
      needsAuth: group.server.unpaired,
      pendingApprovals: pending.approvals,
      pendingQuestions: pending.questions,
      running: group.running.length,
      active: group.server.id == activeServerId,
      error: group.monitor.error,
      onTap: () => onTapDevice(group.server.id),
      expand: expand,
    );
  }
}
