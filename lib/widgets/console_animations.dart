import 'package:flutter/material.dart';

class ConsoleEmptyState extends StatefulWidget {
  const ConsoleEmptyState({super.key});

  @override
  State<ConsoleEmptyState> createState() => _ConsoleEmptyStateState();
}

class _ConsoleEmptyStateState extends State<ConsoleEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.08),
              end: const Offset(0, 0.08),
            ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
            child: const Icon(Icons.radar, size: 56, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          Text('一切安静', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '运行中的会话和待查看的完成会话\n会出现在这里',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 入场：淡入 + 上滑（按 key 只播一次）
class ConsoleEntrance extends StatefulWidget {
  final int index;
  final Widget child;

  const ConsoleEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<ConsoleEntrance> createState() => _ConsoleEntranceState();
}

class _ConsoleEntranceState extends State<ConsoleEntrance> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 70), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: _shown ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        offset: _shown ? Offset.zero : const Offset(0, 0.25),
        child: widget.child,
      ),
    );
  }
}

class ConsolePulseDot extends StatefulWidget {
  const ConsolePulseDot({super.key});

  @override
  State<ConsolePulseDot> createState() => _ConsolePulseDotState();
}

class _ConsolePulseDotState extends State<ConsolePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.6, end: 1.6)
                .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
            child: FadeTransition(
              opacity: Tween(begin: 0.7, end: 0.0).animate(_c),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class ConsoleBreathBadge extends StatefulWidget {
  final String text;
  const ConsoleBreathBadge({super.key, this.text = '!'});

  @override
  State<ConsoleBreathBadge> createState() => _ConsoleBreathBadgeState();
}

class _ConsoleBreathBadgeState extends State<ConsoleBreathBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          widget.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
