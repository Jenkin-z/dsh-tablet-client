import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 工具调用中的状态条 —— iOS 风格
class ToolStatusBar extends StatelessWidget {
  final String toolName;

  const ToolStatusBar({super.key, required this.toolName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: IosTheme.spaceXS,
        horizontal: IosTheme.spaceL,
      ),
      padding: const EdgeInsets.symmetric(
        vertical: IosTheme.spaceM,
        horizontal: IosTheme.spaceL,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C2A3A)
            : IosTheme.iosBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: IosTheme.iosBlue,
            ),
          ),
          const SizedBox(width: IosTheme.spaceM),
          Flexible(
            child: Text(
              '正在调用工具: $toolName …',
              style: const TextStyle(
                fontSize: 14,
                color: IosTheme.iosBlue,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
