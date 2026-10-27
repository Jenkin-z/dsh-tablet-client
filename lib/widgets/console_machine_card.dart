import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import 'device_row_parts.dart';

/// 控制台机器卡片：两行布局（第一行名称，第二行运行/未读数）
///
/// 旧版单行胶囊数量挤在名称后面；改为两行卡片后**宽度按内容收缩**：
/// - 第一行：状态图标 + 名称
/// - 第二行：运行中 / 未读 数量；都为 0 时退回显示机器地址
/// 宽度不设下限（旧版 min 132 会把「PC」这种短名也撑成近 200 宽），
/// 只封顶 [_contentMaxWidth]，名长了才省略，卡片横向不再拖一长条。
/// 点击仍然只切当前机器，不按有没有运行中的会话分叉。
class ConsoleMachineCard extends StatelessWidget {
  final String title;

  /// 第二行兜底文案（通常为机器地址），数量都为 0 时显示
  final String subtitle;
  final bool online;
  final bool needsAuth;
  final int running;
  final int unviewed;
  final String? error;
  final bool active;
  final VoidCallback? onTap;

  /// 纵向栏里宽度是固定的，标题必须可收缩，不能把统计挤出边界
  final bool fillWidth;

  /// 卡片固定高度：纵向条里多台机器高度一致
  static const double cardHeight = 62;

  /// 内容区宽度上限。**不设下限**——按内容收缩，短名卡片自然变窄；
  /// 只有超长别名才会顶到上限后省略。
  static const double contentMaxWidth = 132;

  const ConsoleMachineCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.online,
    required this.needsAuth,
    required this.running,
    required this.unviewed,
    required this.active,
    this.error,
    this.onTap,
    this.fillWidth = false,
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
            borderRadius: BorderRadius.circular(IosTheme.radiusM),
            side: BorderSide(
              color: border,
              width: active ? 1.4 : 0.8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: cardHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: IosTheme.spaceS,
                  vertical: IosTheme.spaceS,
                ),
                child: Row(
                  // min：有界宽度下也按内容收缩（max 会被撑满整行，
                  // 这正是旧版卡片横向拉一长条的原因之一）
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_icon, size: 15, color: statusColor),
                    ),
                    const SizedBox(width: 6),
                    // 纵向栏宽度有界 → Expanded 吃满；横向条宽度无界
                    // → 只封顶不设下限，按内容收缩（短名不撑长卡片）
                    fillWidth
                        ? Expanded(child: _content(isDark))
                        : ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: contentMaxWidth,
                            ),
                            child: _content(isDark),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 名称 + 第二行统计/地址。整体 Expanded：横向条里卡片不再被
  /// 内容撑得忽长忽短，统一吃满高度内的可用宽度。
  Widget _content(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // min：否则这一行会吃满 contentMaxWidth，短名也被撑成固定宽度
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        _secondLine(isDark),
      ],
    );
  }

  Widget _secondLine(bool isDark) {
    final stats = <Widget>[
      if (running > 0)
        DeviceMiniStat(
          icon: Icons.play_arrow_rounded,
          text: '$running',
          color: IosTheme.iosGreen,
        ),
      if (running > 0 && unviewed > 0) const SizedBox(width: IosTheme.spaceS),
      if (unviewed > 0)
        DeviceMiniStat(
          icon: Icons.mark_as_unread_outlined,
          text: '$unviewed',
          color: IosTheme.iosOrange,
        ),
    ];
    if (stats.isNotEmpty) {
      return Row(mainAxisSize: MainAxisSize.min, children: stats);
    }
    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: isDark
            ? Colors.white.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.40),
      ),
    );
  }
}
