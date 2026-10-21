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
    return Switch.adaptive(
      value: value,
      onChanged: enabled ? onChanged : null,
      activeThumbColor: Colors.white,
      activeTrackColor: IosTheme.iosGreen,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: IosTheme.iosGray3,
    );
  }
}

/// 状态点
class IosStatusDot extends StatelessWidget {
  final Color color;
  final double size;

  const IosStatusDot({
    super.key,
    required this.color,
    this.size = 10,
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

/// 徽标
class IosBadge extends StatelessWidget {
  final int count;
  final bool showDot;

  const IosBadge({
    super.key,
    this.count = 0,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showDot) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: IosTheme.iosRed,
          shape: BoxShape.circle,
        ),
      );
    }
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: IosTheme.iosRed,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
