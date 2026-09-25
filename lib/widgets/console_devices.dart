import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import '../services/server_manager.dart';

/// 顶部设备状态卡：一台 PC 一张 —— iOS 风格
class ConsoleDeviceCard extends StatelessWidget {
  final String name;
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
    required this.name,
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
    final statusColor = needsAuth
        ? IosTheme.iosOrange
        : (online ? IosTheme.iosGreen : IosTheme.iosGray);
    // 状态行只说「状态」，不再重复 IP —— IP 只由 hostLabel 呈现一次。
    // 之前这里 online 时显示 hostLabel，而标题恰好也是 IP（name 默认为 host），
    // 于是同一个地址在卡片上出现两遍：一遍带端口、一遍不带。
    final stateText = needsAuth ? '需要重新授权' : (online ? '在线' : '离线');
    // 名字本身就是 IP 时（没自定义过名称），标题显示 host:port 更完整，
    // 状态行只留状态 —— 地址因此只出现一次。
    final hostOnly = hostLabel.contains(':')
        ? hostLabel.substring(0, hostLabel.lastIndexOf(':'))
        : hostLabel;
    final titleText =
        name.trim().isEmpty || name == hostOnly ? hostLabel : name;
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
            padding: const EdgeInsets.all(IosTheme.spaceM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(IosTheme.radiusXS),
                      ),
                      child: Icon(
                        Icons.computer,
                        size: 18,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    Expanded(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: IosTheme.spaceS,
                          vertical: IosTheme.spaceXXS,
                        ),
                        decoration: BoxDecoration(
                          color: IosTheme.iosBlue.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(IosTheme.radiusXS),
                        ),
                        child: const Text(
                          '当前',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: IosTheme.iosBlue,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: IosTheme.spaceS),
                Text(
                  stateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: IosTheme.spaceXS),
                if (online)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: IosTheme.spaceS,
                          vertical: IosTheme.spaceXXS,
                        ),
                        decoration: BoxDecoration(
                          color: IosTheme.iosGreen.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(IosTheme.radiusXS),
                        ),
                        child: Text(
                          '运行 $running',
                          style: const TextStyle(
                            fontSize: 12,
                            color: IosTheme.iosGreen,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (unviewed > 0) ...[
                        const SizedBox(width: IosTheme.spaceS),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: IosTheme.spaceS,
                            vertical: IosTheme.spaceXXS,
                          ),
                          decoration: BoxDecoration(
                            color:
                                IosTheme.iosOrange.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(IosTheme.radiusXS),
                          ),
                          child: Text(
                            '未读 $unviewed',
                            style: const TextStyle(
                              fontSize: 12,
                              color: IosTheme.iosOrange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Text(
                    error ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: IosTheme.iosGray,
                    ),
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
              name: groups[i].server.name,
              // IP 只在这里出现一次（host:port），别处不再重复
              hostLabel: '${groups[i].server.host}:${groups[i].server.port}',
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