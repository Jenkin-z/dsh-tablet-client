import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import '../utils/console_sessions.dart';
import '../utils/session_format.dart';
import 'console_device_chip.dart';

/// 跨机器混排后的一条会话（DESIGN.md §6 会话行）
///
/// 状态点 · 标题 · 机器名 · 相对时间 · NEW 徽标 / 待办 pill。
/// 状态用点/pill 表达，不用图标堆叠；NEW 徽标表达「运行→空闲」
/// 边沿那一刻（即未读），待办 pill 表达等待审批/回答。
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

    final p = IosPalette.of(context);
    final running = session['running'] == true;
    final isCurrent = isActiveServer && sessionId == currentSessionId;
    final pendingKind = pendingKindOf?.call(sessionId);
    final hasPending = pendingKind != null;
    final isUnviewed =
        unviewedKeys.contains(unviewedKeyBuilder(entry.serverId, sessionId));

    // 状态点：待办 warn / 未读 warn / 运行 ok / 当前 accent / 其余 label3
    final dotColor = hasPending || isUnviewed
        ? p.warnTint
        : running
            ? p.ok
            : (isCurrent ? p.accent : p.label3);

    final time = timeAgoOf((session['updatedAt'] as num?)?.toInt());
    final detail = [
      if (hasPending) _pendingLabel(pendingKind),
      if (running) '运行中',
    ].where((s) => s.isNotEmpty).join('，');

    return Semantics(
      button: true,
      label: '${sessionTitleOf(session)}，${entry.serverName}'
          '${detail.isEmpty ? '' : '，$detail'}',
      child: Material(
        color: isCurrent ? p.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: () => onOpenSession(entry.serverId, sessionId),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IosTheme.spaceL,
              vertical: IosTheme.spaceS,
            ),
            child: Row(
              children: [
                IosStatusDot(color: dotColor),
                const SizedBox(width: IosTheme.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sessionTitleOf(session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: IosType.body,
                                fontWeight: isCurrent || running || isUnviewed
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: p.label,
                              ),
                            ),
                          ),
                          if (isUnviewed) ...[
                            const SizedBox(width: IosTheme.spaceS),
                            const IosNewBadge(),
                          ],
                        ],
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
                              time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: IosType.caption,
                                color: p.label3,
                              ),
                            ),
                          ),
                          if (hasPending) ...[
                            const SizedBox(width: IosTheme.spaceS),
                            _pendingPill(context, p, pendingKind),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: IosTheme.spaceS),
                Icon(Icons.chevron_right, size: 18, color: p.label3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _pendingLabel(String? kind) => switch (kind) {
        'approval' => '待审批',
        'question' => '待回答',
        'plan-review' => '待确认',
        _ => '待处理',
      };

  /// 待办 pill：warn 软底 + 文字级 warn
  Widget _pendingPill(BuildContext context, IosPalette p, String? kind) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.warnSoft,
        borderRadius: BorderRadius.circular(IosTheme.radiusPill),
      ),
      child: Text(
        _pendingLabel(kind),
        style: TextStyle(
          fontSize: IosType.caption,
          fontWeight: FontWeight.w500,
          color: p.warnText,
          height: 1.3,
        ),
      ),
    );
  }
}
