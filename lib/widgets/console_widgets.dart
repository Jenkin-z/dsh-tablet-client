import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 呼吸动画徽标
class ConsoleBreathBadge extends StatelessWidget {
  const ConsoleBreathBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return IosBreathingDot(color: IosPalette.of(context).warnTint);
  }
}

/// 列表分节标题（带计数与可选强调徽标）—— iOS 风格
class ConsoleSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final int count;
  final bool badge;
  final Widget? action;

  const ConsoleSectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.count,
    this.badge = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceS,
        IosTheme.spaceL,
        IosTheme.spaceXS,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: IosTheme.spaceS),
          Text(
            title,
            style: TextStyle(
              fontSize: IosType.body,
              fontWeight: FontWeight.w600,
              color: p.label,
            ),
          ),
          const SizedBox(width: IosTheme.spaceS),
          AnimatedSwitcher(
            duration: IosMotion.durationFast,
            child: Container(
              key: ValueKey(count),
              padding: const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceS,
                vertical: IosTheme.spaceXXS,
              ),
              decoration: BoxDecoration(
                color: badge ? p.warnSoft : p.fill,
                borderRadius: BorderRadius.circular(IosTheme.radiusPill),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: IosType.footnote,
                  color: badge ? p.warnText : p.label2,
                  fontWeight: badge ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// 静默文本行 —— iOS 风格
class ConsoleQuietLine extends StatelessWidget {
  final String text;
  const ConsoleQuietLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IosTheme.spaceXXS),
      child: Text(
        text,
        style: TextStyle(
          fontSize: IosType.footnotePlus,
          fontStyle: FontStyle.italic,
          color: IosPalette.of(context).label3,
        ),
      ),
    );
  }
}
