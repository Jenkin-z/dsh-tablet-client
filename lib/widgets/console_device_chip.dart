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
    final p = IosPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceS,
        vertical: IosTheme.spaceXXS,
      ),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(IosTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IosStatusDot(
            color: online ? p.ok : p.label3,
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
                fontSize: IosType.caption,
                color: p.label2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
