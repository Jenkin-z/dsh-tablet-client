import 'package:flutter/material.dart';

import '../widgets/connection_status.dart';
import '../theme/ios_theme.dart';

/// AppBar 标题：连接状态点 + 当前会话名（保持原语义，未做任何改动）
class ChatAppBarTitle extends StatelessWidget {
  const ChatAppBarTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ConnectionStatus(showLabel: false),
        const SizedBox(width: IosTheme.spaceS),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
