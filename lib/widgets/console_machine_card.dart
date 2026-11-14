import 'package:flutter/material.dart';
import '../models/agent_server.dart';
import '../models/poll_beat.dart';
import '../theme/ios_theme.dart';
import 'poll_pulse.dart';

/// 设备卡（DESIGN.md §6，紧凑版：不带设备地址）
///
/// ① 状态点 + 机器名
/// ② 后端徽标（DSH / opencode）
/// ③ 心跳刻度（签名动作）
/// ④ 状态文案（在心跳行下方，宽度不超过刻度行）+ 运行数
/// ⑤ 待办行：审批 / 提问计数（有待办才显示）
class ConsoleMachineCard extends StatelessWidget {
  final String title;

  /// 后端类型徽标（DSH / opencode）
  final AgentKind kind;
  final List<PollBeat> beats;
  final bool online;
  final bool needsAuth;

  /// 待办角标：该机器上等待审批/提问的会话数
  final int pendingApprovals;
  final int pendingQuestions;
  final int running;
  final String? error;
  final bool active;
  final VoidCallback? onTap;

  /// 充满可用宽度（竖栏侧边栏用）；默认 false——横排条按内容收缩
  final bool expand;

  /// 卡片固定高度：横向条与纵向栏里多台机器高度一致
  static const double cardHeight = 108;

  /// 内容区宽度上限；**不设下限**——按内容收缩，短名卡片自然变窄
  static const double contentMaxWidth = 168;

  const ConsoleMachineCard({
    super.key,
    required this.title,
    required this.kind,
    required this.beats,
    required this.online,
    required this.needsAuth,
    required this.pendingApprovals,
    required this.pendingQuestions,
    required this.running,
    required this.active,
    this.error,
    this.onTap,
    this.expand = false,
  });

  String get _statusLabel {
    if (needsAuth) return '需要重新授权';
    return online ? '在线' : (error ?? '离线');
  }

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    final statusColor = needsAuth
        ? p.warnTint
        : online
            ? p.ok
            : p.bad;
    final bg = active ? p.accentSoft : p.surface;
    final border = active ? p.accent.withValues(alpha: 0.55) : p.separator;

    return Semantics(
      button: true,
      selected: active,
      label: '$title，$_statusLabel'
          '${running > 0 ? '，$running 个运行中' : ''}'
          '${pendingApprovals + pendingQuestions > 0 ? '，待处理 $pendingApprovals 项审批、$pendingQuestions 项提问' : ''}',
      child: Tooltip(
        message: '$title · $_statusLabel',
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusS),
            side: BorderSide(color: border, width: active ? 1.2 : 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: cardHeight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ConstrainedBox(
                  // 横排条按内容收缩（封顶）；竖栏侧边栏 expand 充满可用宽度
                  constraints: expand
                      ? const BoxConstraints()
                      : const BoxConstraints(maxWidth: contentMaxWidth),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _titleRow(p, statusColor),
                      const SizedBox(height: 4),
                      _kindBadge(p),
                      const SizedBox(height: 4),
                      PollPulse(beats: beats),
                      const SizedBox(height: 4),
                      _statusRow(p),
                      if (pendingApprovals + pendingQuestions > 0) ...[
                        const SizedBox(height: 4),
                        _pendingRow(p),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ① 状态点 + 机器名
  Widget _titleRow(IosPalette p, Color statusColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IosStatusDot(color: statusColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: IosType.footnotePlus,
              fontWeight: FontWeight.w600,
              color: p.label,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  /// ② 后端徽标（DSH / opencode）
  Widget _kindBadge(IosPalette p) {
    final label = switch (kind) {
      AgentKind.dsh => 'DSH',
      AgentKind.opencode => 'opencode',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(IosTheme.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: IosType.mono,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: p.accent,
          height: 1.3,
        ),
      ),
    );
  }

  /// ④ 状态文案（宽度钳制在心跳刻度行内）+ 运行数
  Widget _statusRow(IosPalette p) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: PollPulse.rowWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              online ? '8s 轮询' : (error ?? '离线'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: online ? p.label3 : p.bad,
                height: 1.3,
              ),
            ),
          ),
          if (running > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$running 运行中',
              style: TextStyle(
                fontSize: 10,
                color: p.ok,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ④ 待办行：count badge + 审批/提问明细
  Widget _pendingRow(IosPalette p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: p.warnTint,
            borderRadius: BorderRadius.circular(IosTheme.radiusPill),
          ),
          child: Text(
            '${pendingApprovals + pendingQuestions}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: p.onAccent,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '待处理 · 审批 $pendingApprovals · 提问 $pendingQuestions',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: IosType.caption, color: p.label2),
          ),
        ),
      ],
    );
  }
}
