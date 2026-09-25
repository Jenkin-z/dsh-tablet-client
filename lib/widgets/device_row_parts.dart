import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 设备在线状态图标 —— 单行卡片右侧那个图标
///
/// 在线状态**只用图标**表达（用户明确要求），不再占一行文字：
/// - 在线：绿色对勾
/// - 离线：红色断开图标（`cloud_off` 自带斜线，等价「红底加斜线」）
/// - 需授权：橙色锁
///
/// 图标本身说明不了原因，所以挂 Tooltip，点一下能看到具体错误。
class DeviceStatusIcon extends StatelessWidget {
  final bool online;
  final bool needsAuth;
  final String? error;

  const DeviceStatusIcon({
    super.key,
    required this.online,
    required this.needsAuth,
    this.error,
  });

  IconData get _icon {
    if (needsAuth) return Icons.lock_outline;
    return online ? Icons.check_circle : Icons.cloud_off;
  }

  Color get color {
    if (needsAuth) return IosTheme.iosOrange;
    return online ? IosTheme.iosGreen : IosTheme.iosRed;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: needsAuth ? '需要重新授权' : (online ? '在线' : (error ?? '离线')),
      triggerMode: TooltipTriggerMode.tap,
      child: Icon(_icon, size: 20, color: color),
    );
  }
}

/// 行内的小统计（运行中 / 未读数）：图标 + 数字
class DeviceMiniStat extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const DeviceMiniStat({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 「当前」徽章
class DeviceActiveBadge extends StatelessWidget {
  const DeviceActiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceS,
        vertical: IosTheme.spaceXXS,
      ),
      decoration: BoxDecoration(
        color: IosTheme.iosBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IosTheme.radiusXS),
      ),
      child: const Text(
        '当前',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: IosTheme.iosBlue,
        ),
      ),
    );
  }
}
