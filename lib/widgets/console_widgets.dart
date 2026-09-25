import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 呼吸动画徽标
class ConsoleBreathBadge extends StatelessWidget {
  const ConsoleBreathBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceXXS,
        IosTheme.spaceS,
        0,
        IosTheme.spaceXS,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: IosTheme.spaceS),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: IosTheme.spaceS),
          AnimatedSwitcher(
            duration: IosTheme.durationFast,
            child: Container(
              key: ValueKey(count),
              padding: const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceS,
                vertical: IosTheme.spaceXXS,
              ),
              decoration: BoxDecoration(
                color: badge
                    ? IosTheme.iosOrange
                    : Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(IosTheme.radiusXS),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: badge
                      ? Colors.white
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                  fontWeight: badge ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
          if (badge) ...[
            const SizedBox(width: IosTheme.spaceS),
            ConsoleBreathBadge(),
          ],
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
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: IosTheme.iosGray,
        ),
      ),
    );
  }
}
