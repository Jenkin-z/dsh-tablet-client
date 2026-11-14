part of 'ios_theme.dart';

/// iOS 风格开关
class IosSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const IosSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Switch.adaptive(
      value: value,
      onChanged: enabled ? onChanged : null,
      activeThumbColor: p.isDark ? p.onAccent : Colors.white,
      activeTrackColor: p.accent,
      inactiveThumbColor: p.isDark ? p.label2 : Colors.white,
      inactiveTrackColor: p.isDark ? p.surface2 : p.fill,
    );
  }
}

/// 状态点（DESIGN.md §6：8pt 圆点 + 语义色；connecting 橙呼吸）
class IosStatusDot extends StatelessWidget {
  final Color color;

  /// 设计基准 8pt
  final double size;

  const IosStatusDot({
    super.key,
    required this.color,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 呼吸状态点（connecting 态：1.6s 周期缩放+淡出，表达"正在连接"）
class IosBreathingDot extends StatefulWidget {
  final Color color;
  final double size;

  const IosBreathingDot({
    super.key,
    required this.color,
    this.size = 8,
  });

  @override
  State<IosBreathingDot> createState() => _IosBreathingDotState();
}

class _IosBreathingDotState extends State<IosBreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
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
        final t = Curves.easeInOut.transform(_controller.value);
        final halo = widget.color.withValues(alpha: 0.35 * (1 - t));
        return SizedBox(
          width: widget.size * 2.2,
          height: widget.size * 2.2,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: widget.size + widget.size * t * 1.2,
                  height: widget.size + widget.size * t * 1.2,
                  decoration: BoxDecoration(color: halo, shape: BoxShape.circle),
                ),
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 徽标
class IosBadge extends StatelessWidget {
  final int count;
  final bool showDot;

  /// 徽标主色；默认 bad（未读/待办），NEW 徽标用 warn
  final Color? color;

  const IosBadge({
    super.key,
    this.count = 0,
    this.showDot = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    final c = color ?? p.bad;
    if (showDot) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
    }
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(IosTheme.radiusPill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: p.onAccent,
          fontSize: IosType.footnote,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

/// NEW 徽标（DESIGN.md §2 辅助签名：一枚点 + 描边圆角胶囊，表达"这一刻"）
class IosNewBadge extends StatelessWidget {
  const IosNewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.warnSoft,
        borderRadius: BorderRadius.circular(IosTheme.radiusPill),
        border: Border.all(color: p.warnTint, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: p.warnTint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'NEW',
            style: TextStyle(
              color: p.warnText,
              fontSize: IosType.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
