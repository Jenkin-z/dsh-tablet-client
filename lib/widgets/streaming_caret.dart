import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 流式输出光标（DESIGN.md §7：2px 竖条，1s 步进闪烁）
class StreamingCaret extends StatefulWidget {
  final Color color;

  const StreamingCaret({super.key, required this.color});

  @override
  State<StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: IosMotion.durationCaret,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 步进闪烁：半周期亮、半周期灭
        final visible = _controller.value < 0.5;
        return Container(
          width: 2,
          height: 16,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: visible ? widget.color : Colors.transparent,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}
