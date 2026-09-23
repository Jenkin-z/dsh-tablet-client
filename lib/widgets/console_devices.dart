import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

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
    final stateText =
        needsAuth ? '需要重新授权' : (online ? hostLabel : '离线');
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
                        name,
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
