import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';
import '../utils/session_format.dart';
import 'console_animations.dart';
import 'console_device_chip.dart';

/// 合并会话列表里的单条会话
///
/// 从 console_merged_tile.dart 拆出来，让那个文件守住 200 行上限。
/// 图标/颜色优先级：待办 > 未读 > 运行中 > 当前 > 普通。
class ConsoleMergedSessionRow extends StatelessWidget {
  final Map<String, dynamic> session;

  /// 服务器名（设备归属徽章）
  final String serverName;

  /// 该服务器在线状态（设备归属徽章）
  final bool serverOnline;

  /// 这条会话是不是当前对话的那台
  final bool isCurrent;

  /// 未读
  final bool isUnviewed;

  /// 运行中
  final bool running;

  /// 待处理交互类型：`approval` / `question` / `plan-review`，无则 null
  final bool hasPending;

  final VoidCallback onTap;

  const ConsoleMergedSessionRow({
    super.key,
    required this.session,
    required this.serverName,
    required this.serverOnline,
    required this.isCurrent,
    required this.isUnviewed,
    required this.running,
    required this.hasPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = hasPending || isUnviewed
        ? IosTheme.iosOrange
        : running
            ? IosTheme.iosGreen
            : (isCurrent ? IosTheme.iosBlue : IosTheme.iosGray);

    final IconData icon;
    if (hasPending) {
      icon = Icons.error_outline;
    } else if (isUnviewed) {
      icon = Icons.mark_as_unread_outlined;
    } else if (session['blank'] == true) {
      icon = Icons.chat_bubble_outline;
    } else {
      icon = Icons.chat_bubble;
    }

    return Material(
      color: isCurrent
          ? IosTheme.iosBlue.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IosTheme.spaceL,
            vertical: IosTheme.spaceS,
          ),
          child: Row(
            children: [
              // 运行中保留脉冲动画；有待办时脉冲让位给告警图标
              if (running && !hasPending)
                const ConsolePulseDot()
              else
                Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: IosTheme.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionTitleOf(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isCurrent || running || isUnviewed
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // 设备归属徽章：重构前有这个，别丢
                        ConsoleDeviceChip(
                          name: serverName,
                          online: serverOnline,
                        ),
                        const SizedBox(width: IosTheme.spaceXS),
                        Expanded(
                          child: Text(
                            '${timeAgoOf(session['updatedAt'] as int?)}'
                            '${isCurrent ? ' · 当前' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: IosTheme.iosGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: IosTheme.iosGray3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
