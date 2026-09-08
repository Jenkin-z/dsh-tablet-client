import 'package:flutter/material.dart';
import '../utils/session_format.dart';
import 'console_animations.dart';

/// 顶部设备状态卡：一台 PC 一张
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
    final theme = Theme.of(context);
    final statusColor =
        needsAuth ? Colors.orange : (online ? Colors.green : Colors.grey);
    final stateText = needsAuth
        ? '需要重新授权'
        : (online ? hostLabel : '离线');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: active
            ? BorderSide(color: theme.colorScheme.primary, width: 1.4)
            : BorderSide(color: theme.dividerColor, width: 0.6),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.computer, size: 16, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  if (active)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('当前', style: TextStyle(fontSize: 10)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                stateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: statusColor),
              ),
              const SizedBox(height: 4),
              if (online)
                Row(
                  children: [
                    Text(
                      '运行 $running',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '未读 $unviewed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: unviewed > 0 ? Colors.orange : null,
                        fontWeight:
                            unviewed > 0 ? FontWeight.bold : null,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  error ?? ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 会话条目上的设备归属徽章
class ConsoleDeviceChip extends StatelessWidget {
  final String name;
  final bool online;

  const ConsoleDeviceChip(
      {super.key, required this.name, required this.online});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          Text(name, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// 合并会话列表条目：跨设备 + 3 小时窗口
class ConsoleMergedTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final String deviceName;
  final bool deviceOnline;
  final bool isCurrent;
  final bool isUnviewed;
  final VoidCallback onTap;

  const ConsoleMergedTile({
    super.key,
    required this.session,
    required this.deviceName,
    required this.deviceOnline,
    required this.isCurrent,
    required this.isUnviewed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final running = session['running'] == true;
    final subtitle =
        '${timeAgoOf(session['updatedAt'] as int?)}${isCurrent ? ' · 当前' : ''}';
    return ListTile(
      dense: true,
      leading: running
          ? const ConsolePulseDot()
          : Icon(
              isUnviewed
                  ? Icons.mark_as_unread_outlined
                  : Icons.chat_bubble_outline,
              size: 20,
              color: isUnviewed ? Colors.orange : null,
            ),
      title: Text(
        sessionTitleOf(session),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isUnviewed || running ? FontWeight.bold : null,
        ),
      ),
      subtitle: Row(
        children: [
          ConsoleDeviceChip(name: deviceName, online: deviceOnline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      trailing: Icon(running ? Icons.chevron_right : Icons.chevron_right,
          size: 20),
      onTap: onTap,
    );
  }
}
