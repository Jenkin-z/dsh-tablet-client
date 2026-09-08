import 'package:flutter/material.dart';
import 'console_animations.dart';

export 'console_animations.dart';

/// 列表分节标题（带计数与可选强调徽标）
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
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(count),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badge
                    ? Colors.orange
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: badge ? Colors.white : null,
                  fontWeight: badge ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
          if (badge) ...[
            const SizedBox(width: 6),
            const ConsoleBreathBadge(),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class ConsoleQuietLine extends StatelessWidget {
  final String text;
  const ConsoleQuietLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}
