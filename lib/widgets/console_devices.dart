import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import '../services/server_manager.dart';
import 'device_row_parts.dart';

/// 顶部设备行：一台 PC 一行 —— iOS 风格
///
/// 布局按用户要求压成单行：
/// `[图标] [别名]  ...  [运行数] [未读数] [当前] [状态图标]`
///
/// 在线状态**只由右侧图标表达**（绿勾 = 在线，红斜线 = 离线），
/// 不再占用一行文字，卡片因此比原来矮一半。
class ConsoleDeviceCard extends StatelessWidget {
  /// 主标题：**服务器别名**（`AgentServer.name`，空则退回地址）。
  /// 曾经直接显示 host —— opencode 隧道条目会露出一串隧道域名，
  /// 看着像 id，用户明确要求显示别名。
  final String title;
  final bool online;
  final bool needsAuth;
  final int running;
  final int unviewed;
  final String? error;
  final bool active;
  final VoidCallback? onTap;

  const ConsoleDeviceCard({
    super.key,
    required this.title,
    required this.online,
    required this.needsAuth,
    required this.running,
    required this.unviewed,
    required this.active,
    this.error,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 在线状态用一个图标表达。离线是「红底 + 斜线」，一眼可辨，
    // 不再需要「在线 / 离线」这行文字。
    final Color statusColor;
    if (needsAuth) {
      statusColor = IosTheme.iosOrange;
    } else if (online) {
      statusColor = IosTheme.iosGreen;
    } else {
      statusColor = IosTheme.iosRed;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        border: active
            ? Border.all(color: IosTheme.iosBlue, width: 1.5)
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: IosTheme.iosBlue.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : IosTheme.shadowS,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(IosTheme.radiusCard),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IosTheme.spaceM,
              vertical: IosTheme.spaceS,
            ),
            child: Row(
              children: [
                // 左：图标（颜色跟随状态，扫一眼就知道好坏）
                Icon(Icons.computer, size: 20, color: statusColor),
                const SizedBox(width: IosTheme.spaceS),
                // 中：别名（没有别名的条目退回地址显示）
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: IosTheme.spaceS),
                // 右：其它信息
                if (active) ...[
                  const DeviceActiveBadge(),
                  const SizedBox(width: IosTheme.spaceS),
                ],
                if (online && running > 0) ...[
                  DeviceMiniStat(
                    icon: Icons.play_circle_outline,
                    text: '$running',
                    color: IosTheme.iosGreen,
                  ),
                  const SizedBox(width: IosTheme.spaceS),
                ],
                if (online && unviewed > 0) ...[
                  DeviceMiniStat(
                    icon: Icons.mark_as_unread_outlined,
                    text: '$unviewed',
                    color: IosTheme.iosOrange,
                  ),
                  const SizedBox(width: IosTheme.spaceS),
                ],
                // 最右：在线状态图标（绿勾 / 红色断开 / 橙色锁）
                DeviceStatusIcon(
                  online: online,
                  needsAuth: needsAuth,
                  error: error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设备列表区域
class ConsoleDevices extends StatelessWidget {
  final List<ServerGroup> groups;
  final void Function(String serverId) onTapDevice;

  /// 当前正在对话的 PC（来自权威状态源），null 表示未连接
  final String? activeServerId;

  const ConsoleDevices({
    super.key,
    required this.groups,
    required this.onTapDevice,
    this.activeServerId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      child: Column(
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: IosTheme.spaceS),
            ConsoleDeviceCard(
              // 别名优先，空名退回地址（防御旧数据）
              title: groups[i].server.name.isEmpty
                  ? groups[i].server.host
                  : groups[i].server.name,
              online: groups[i].monitor.online,
              needsAuth: groups[i].server.unpaired,
              running: groups[i].running.length,
              unviewed: groups[i].unviewed.length,
              error: groups[i].monitor.error,
              active: groups[i].server.id == activeServerId,
              onTap: () => onTapDevice(groups[i].server.id),
            ),
          ],
        ],
      ),
    );
  }
}