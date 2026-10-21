import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import '../utils/console_sessions.dart';
import '../utils/session_format.dart';
import 'console_animations.dart';
import 'console_device_chip.dart';

/// 跨机器混排后的一条会话
///
/// 图标/配色沿用原控制台：待办橙、未读橙、运行中绿、当前蓝。
/// 设备归属从分组标题挪到每行的 [ConsoleDeviceChip]，这样去掉
/// 按机器分组的标题后仍能一眼看出任务在哪台机器上。
class ConsoleSessionTile extends StatelessWidget {
  final ConsoleSessionEntry entry;
  final String? currentSessionId;
  final bool isActiveServer;
  final Set<String> unviewedKeys;
  final String Function(String serverId, String sessionId) unviewedKeyBuilder;
  final String? Function(String sessionId)? pendingKindOf;
  final void Function(String serverId, String sessionId) onOpenSession;

  const ConsoleSessionTile({
    super.key,
    required this.entry,
    required this.unviewedKeys,
    required this.unviewedKeyBuilder,
    required this.onOpenSession,
    this.currentSessionId,
    this.isActiveServer = false,
    this.pendingKindOf,
  });

  @override
  Widget build(BuildContext context) {
    final session = entry.session;
    final sessionId = session['sessionId'] as String? ?? '';
    if (sessionId.isEmpty) return const SizedBox.shrink();

    final running = session['running'] == true;
    final isCurrent = isActiveServer && sessionId == currentSessionId;
    final pendingKind = pendingKindOf?.call(sessionId);
    final hasPending = pendingKind != null;
    final isUnviewed =
        unviewedKeys.contains(unviewedKeyBuilder(entry.serverId, sessionId));

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
    } else {
      icon = Icons.chat_bubble;
    }

    final status = _statusOf(
      hasPending: hasPending,
      pendingKind: pendingKind,
      isUnviewed: isUnviewed,
      running: running,
    );
    final meta = [
      timeAgoOf((session['updatedAt'] as num?)?.toInt()),
      if (isCurrent) '当前',
      if (status.isNotEmpty) status,
    ].where((s) => s.isNotEmpty).join(' · ');
    final detail = [
      if (isCurrent) '当前',
      if (status.isNotEmpty) status,
    ].join('，');

    return Semantics(
      button: true,
      label: '${sessionTitleOf(session)}，${entry.serverName}'
          '${detail.isEmpty ? '' : '，$detail'}',
      child: Material(
        color: isCurrent
            ? IosTheme.iosBlue.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: () => onOpenSession(entry.serverId, sessionId),
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
                          ConsoleDeviceChip(
                            name: entry.serverName,
                            online: entry.online,
                          ),
                          const SizedBox(width: IosTheme.spaceXS),
                          Expanded(
                            child: Text(
                              meta,
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
      ),
    );
  }

  String _statusOf({
    required bool hasPending,
    required String? pendingKind,
    required bool isUnviewed,
    required bool running,
  }) {
    if (hasPending) {
      return switch (pendingKind) {
        'approval' => '待审批',
        'question' => '待回答',
        'plan-review' => '待确认',
        _ => '待处理',
      };
    }
    if (isUnviewed) return '未读';
    if (running) return '运行中';
    return '';
  }
}
