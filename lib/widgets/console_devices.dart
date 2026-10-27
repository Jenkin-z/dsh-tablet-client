import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../theme/ios_theme.dart';
import 'console_machine_card.dart';

/// 顶部机器选择条：横向滚动的两行小卡片
///
/// 名称一行、运行/未读数一行；点击只切当前机器，
/// 不按有没有运行中的会话分叉。
class ConsoleDevices extends StatelessWidget {
  final List<ServerGroup> groups;
  final void Function(String serverId) onTapDevice;

  /// 当前正在对话的 PC（来自权威状态源），null 表示未连接
  final String? activeServerId;

  /// 竖屏用横向卡片条，横屏用左侧纵向列表
  final Axis axis;

  const ConsoleDevices({
    super.key,
    required this.groups,
    required this.onTapDevice,
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
        // 左对齐：卡片按内容收缩，不满宽拉伸（ListView 默认会撑满）
        itemBuilder: (context, i) =>
            Align(alignment: Alignment.centerLeft, child: _card(context, i)),
      );
    }

    return SizedBox(
      height: 70,
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

  Widget _card(BuildContext context, int i) {
    final group = groups[i];
    final name = group.server.name;
    final host = group.server.host;
    return ConsoleMachineCard(
      // 别名优先，空名退回地址（防御旧数据）
      title: name.isNotEmpty ? name : (host.isNotEmpty ? host : 'PC'),
      subtitle: host,
      online: group.monitor.online,
      needsAuth: group.server.unpaired,
      running: group.running.length,
      unviewed: group.unviewed.length,
      error: group.monitor.error,
      active: group.server.id == activeServerId,
      onTap: () => onTapDevice(group.server.id),
    );
  }
}
