import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import '../services/server_manager.dart';
import 'device_row_parts.dart';

/// 顶部设备行：一台 PC 一行 —— iOS 风格
///
/// 布局按用户要求压成单行：
/// `[图标] [地址]  ...  [运行数] [未读数] [当前] [状态图标]`
///
/// 在线状态**只由右侧图标表达**（绿勾 = 在线，红斜线 = 离线），
/// 不再占用一行文字，卡片因此比原来矮一半。
class ConsoleDeviceCard extends StatelessWidget {
  /// 显示地址：**不含端口**（用户明确要求）。
  ///
  /// 代价是同一 IP 上跑两个实例时看着一样。DSH 默认端口固定，
  /// 单机单实例是常态，所以按可读性优先。
  final String hostLabel;
  final bool online;
  final bool needsAuth;
  final int running;
  final int unviewed;
  final String? error;
  final bool active;
  final VoidCallback? onTap;

  const ConsoleDeviceCard({
    super.key,
    required this.hostLabel,
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
                // 中：地址（只显示 IP，不带端口）
                Expanded(
                  child: Text(
                    hostLabel,
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

/// 会话条目上的设备归属徽章 —— iOS 风格
class ConsoleDeviceChip extends StatelessWidget {
  final String name;
  final bool online;

  const ConsoleDeviceChip(
      {super.key, required this.name, required this.online});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceS,
        vertical: IosTheme.spaceXXS,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(IosTheme.radiusXS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IosStatusDot(
            color: online ? IosTheme.iosGreen : IosTheme.iosGray,
            size: 6,
          ),
          const SizedBox(width: IosTheme.spaceXS),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
        ],
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
              // 地址只显示 host，不带端口
              hostLabel: groups[i].server.host,
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