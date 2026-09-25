import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../theme/ios_theme.dart';
import '../utils/session_format.dart';
import 'console_animations.dart';
import 'console_devices.dart';

/// 合并会话列表条目：按服务器分组，只显示窗口期内活跃的会话
///
/// 图标/配色沿用重构前 ConsoleMergedTile 的那一套（未读橙、运行中脉冲、
/// 设备归属徽章），并补上侧栏已有的「待办 > 未读 > 运行中」优先级。
/// 两页对同一会话必须显示同一状态，否则用户没法信任何一个。
class ConsoleMergedTile extends StatelessWidget {
  final ServerGroup group;

  /// 当前正在对话的会话（来自权威状态源），用于高亮
  final String? currentSessionId;

  /// 活跃窗口：只显示这段时间内更新过的会话（重构前是 3 小时）
  final Duration window;

  /// 本机未读会话的 key 集合（settings.seenKey 口径）
  final Set<String> unviewedKeys;

  /// 生成未读 key 的函数，由调用方注入以免这里依赖 SettingsService
  final String Function(String serverId, String sessionId) unviewedKeyBuilder;

  final void Function(String sessionId) onOpenSession;

  /// 待处理交互类型：`approval` / `question` / `plan-review`，无则 null
  final String? Function(String sessionId)? pendingKindOf;

  /// 这台机器是否就是当前对话的那台
  ///
  /// 与设备卡上的「当前」是同一件事，两处必须一致，
  /// 否则用户不知道「当前」到底指什么。
  final bool isActiveServer;

  const ConsoleMergedTile({
    super.key,
    required this.group,
    required this.onOpenSession,
    required this.unviewedKeys,
    required this.unviewedKeyBuilder,
    required this.window,
    this.currentSessionId,
    this.pendingKindOf,
    this.isActiveServer = false,
  });

  /// 窗口期内的会话：去重、过滤空会话与已归档、按最近活动倒序
  List<Map<String, dynamic>> _recent() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - window.inMilliseconds;
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final s in [
      ...group.running,
      ...group.unviewed,
      ...group.recent,
    ]) {
      final id = s['sessionId'] as String? ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      if (s['blank'] == true) continue;
      if (group.monitor.archivedIds.contains(id)) continue;
      final updatedAt = (s['updatedAt'] as num?)?.toInt() ?? 0;
      if (updatedAt < cutoff) continue;
      out.add(s);
    }
    out.sort((a, b) =>
        ((b['updatedAt'] as num?)?.toInt() ?? 0)
            .compareTo((a['updatedAt'] as num?)?.toInt() ?? 0));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _recent();
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, sessions.length),
        ...sessions.map((s) => _sessionTile(context, s)),
      ],
    );
  }

  Widget _header(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceS,
      ),
      child: Row(
        children: [
          Icon(
            Icons.computer,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: IosTheme.spaceS),
          Text(
            group.server.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: IosTheme.spaceS),
          Text(
            '$count',
            style: const TextStyle(fontSize: 13, color: IosTheme.iosGray),
          ),
          if (isActiveServer) ...[
            const SizedBox(width: IosTheme.spaceS),
            Container(
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
            ),
          ],
        ],
      ),
    );
  }

  /// 图标/颜色优先级：待办 > 未读 > 运行中 > 当前 > 普通
  Widget _sessionTile(BuildContext context, Map<String, dynamic> session) {
    final sessionId = session['sessionId'] as String? ?? '';
    if (sessionId.isEmpty) return const SizedBox.shrink();

    final running = session['running'] == true;
    final isCurrent = sessionId == currentSessionId;
    final hasPending = pendingKindOf?.call(sessionId) != null;
    final isUnviewed = unviewedKeys
        .contains(unviewedKeyBuilder(group.server.id, sessionId));

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
        onTap: () => onOpenSession(sessionId),
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
                          name: group.server.name,
                          online: group.monitor.online,
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
