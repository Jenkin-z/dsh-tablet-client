import 'package:flutter/material.dart';
import 'console_animations.dart';

export 'console_animations.dart';
export 'console_cards.dart';

/// 顶部统计条：运行中 / 待查看 / 全部
class ConsoleStatStrip extends StatelessWidget {
  final int running;
  final int unviewed;
  final int total;

  const ConsoleStatStrip({
    super.key,
    required this.running,
    required this.unviewed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: Icons.sync,
            label: '运行中',
            value: running,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: Icons.mark_as_unread_outlined,
            label: '待查看',
            value: unviewed,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: Icons.forum_outlined,
            label: '全部会话',
            value: total,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                '$value',
                key: ValueKey(value),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

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
