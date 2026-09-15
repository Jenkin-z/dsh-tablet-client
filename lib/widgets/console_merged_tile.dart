import 'package:flutter/material.dart';
import '../utils/session_format.dart';
import 'console_animations.dart';
import 'console_devices.dart';

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
