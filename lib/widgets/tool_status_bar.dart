import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 工具调用中的状态条
class ToolStatusBar extends StatelessWidget {
  final String toolName;

  const ToolStatusBar({super.key, required this.toolName});

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
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
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(IosTheme.radiusS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: p.accent,
            ),
          ),
          const SizedBox(width: IosTheme.spaceM),
          Flexible(
            child: Text(
              '正在调用工具: $toolName …',
              style: TextStyle(
                fontSize: IosType.footnotePlus,
                color: p.accent,
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
