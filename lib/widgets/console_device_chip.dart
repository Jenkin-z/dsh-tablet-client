import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 会话条目上的设备归属徽章 —— iOS 风格
class ConsoleDeviceChip extends StatelessWidget {
  final String name;
  final bool online;

  const ConsoleDeviceChip(
      {super.key, required this.name, required this.online});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceS,
        vertical: IosTheme.spaceXXS,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(IosTheme.radiusXS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IosStatusDot(
            color: online ? IosTheme.iosGreen : IosTheme.iosGray,
            size: 6,
          ),
          const SizedBox(width: IosTheme.spaceXS),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
