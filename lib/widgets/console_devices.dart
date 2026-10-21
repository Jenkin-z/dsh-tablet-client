import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../theme/ios_theme.dart';
import 'device_row_parts.dart';

/// 顶部机器选择条：横向滚动的紧凑胶囊
///
/// 旧版一台机器一张全宽卡片，三台机器就吃掉半屏；现在整条只有 44 高，
/// 名称、在线状态、运行/未读数都在同一行。点击仍然只切当前机器，
/// 不按有没有运行中的会话分叉。
class ConsoleMachineChip extends StatelessWidget {
  final String title;
  final bool online;
  final bool needsAuth;
  final int running;
  final int unviewed;
  final String? error;
  final bool active;
  final VoidCallback? onTap;

  const ConsoleMachineChip({
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

  IconData get _icon {
    if (needsAuth) return Icons.lock_outline_rounded;
    if (!online) return Icons.cloud_off_rounded;
    return Icons.computer_rounded;
  }

  Color get _statusColor {
    if (needsAuth) return IosTheme.iosOrange;
    return online ? IosTheme.iosGreen : IosTheme.iosRed;
  }

  String get _statusLabel {
    if (needsAuth) return '需要重新授权';
    return online ? '在线' : (error ?? '离线');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor;
    final bg = active
        ? IosTheme.iosBlue.withValues(alpha: isDark ? 0.22 : 0.10)
        : (isDark ? const Color(0xFF1C1C1E) : Colors.white);
    final border = active
        ? IosTheme.iosBlue.withValues(alpha: 0.55)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06));
    final radius = BorderRadius.circular(IosTheme.radiusChip);

    return Semantics(
      button: true,
      selected: active,
      label: '$title，$_statusLabel'
          '${running > 0 ? '，$running 个运行中' : ''}'
          '${unviewed > 0 ? '，$unviewed 条未读' : ''}',
      child: Tooltip(
        message: '$title · $_statusLabel',
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: border,
              width: active ? 1.4 : 0.8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: IosTheme.spaceM,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(_icon, size: 17, color: statusColor),
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 132),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (running > 0) ...[
                      const SizedBox(width: IosTheme.spaceS),
                      DeviceMiniStat(
                        icon: Icons.play_arrow_rounded,
                        text: '$running',
                        color: IosTheme.iosGreen,
                      ),
                    ],
                    if (unviewed > 0) ...[
                      const SizedBox(width: 6),
                      DeviceMiniStat(
                        icon: Icons.mark_as_unread_outlined,
                        text: '$unviewed',
                        color: IosTheme.iosOrange,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设备选择条：横向滚动，避免多台机器把纵向空间吃光
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
    if (groups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: IosTheme.spaceS),
        itemBuilder: (context, i) {
          final group = groups[i];
          final name = group.server.name;
          final host = group.server.host;
          return ConsoleMachineChip(
            // 别名优先，空名退回地址（防御旧数据）
            title: name.isNotEmpty ? name : (host.isNotEmpty ? host : 'PC'),
            online: group.monitor.online,
            needsAuth: group.server.unpaired,
            running: group.running.length,
            unviewed: group.unviewed.length,
            error: group.monitor.error,
            active: group.server.id == activeServerId,
            onTap: () => onTapDevice(group.server.id),
          );
        },
      ),
    );
  }
}
