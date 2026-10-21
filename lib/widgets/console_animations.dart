import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

export 'console_animations_parts.dart' show ConsoleStatsCard, ConsoleEmptyState;

/// 控制台动画组件
/// 统计卡片与空状态拆到 console_animations_parts.dart，让本文件守住 200 行上限。
class ConsolePulseDot extends StatefulWidget {
  const ConsolePulseDot({super.key});

  @override
  State<ConsolePulseDot> createState() => _ConsolePulseDotState();
}

class _ConsolePulseDotState extends State<ConsolePulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: IosTheme.iosGreen.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
          child: child,
        );
      },
      child: const Icon(
        Icons.play_arrow,
        size: 12,
        color: Colors.white,
      ),
    );
  }
}

/// 入场动画
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
